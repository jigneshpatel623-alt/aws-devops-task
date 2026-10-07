"""Demo web application for the AWS DevOps practical task.

Pages
- "/"                 : dashboard (instance / AZ / DB status) + feedback form
- "/submissions"      : all saved submissions with search, category filter, pagination
- "/submit"  (POST)   : validates and saves a submission to RDS MySQL
- "/api/submissions"  : latest submissions as JSON
- "/health"           : liveness check used by the ALB target group
- "/db-health"        : database connectivity check

DB credentials come from AWS Secrets Manager at runtime; nothing is hard-coded.
"""
import hashlib
import hmac
import json
import math
import os
import re
import secrets
import time
import urllib.request

import boto3
import pymysql
import pymysql.cursors
from flask import Flask, flash, jsonify, redirect, render_template, request, session, url_for

app = Flask(__name__)
app.config.update(
    SESSION_COOKIE_SECURE=True,
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    MAX_CONTENT_LENGTH=16 * 1024,
)

REGION = os.environ.get("AWS_REGION", "ap-south-1")
SECRET_ARN = os.environ.get("DB_SECRET_ARN", "")
CA_BUNDLE = os.environ.get("DB_CA_BUNDLE", "/opt/webapp/rds-ca-bundle.pem")
APP_VERSION = os.environ.get("APP_VERSION", "dev")[:7]
STARTED_AT = time.time()
PAGE_SIZE = 20
CATEGORIES = ["Feedback", "Question", "Bug report", "Feature request", "Other"]
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

_secret_cache = None
_schema_ready = False
_meta_cache = {}


# ---------------------------------------------------------------------------
# AWS / database helpers
# ---------------------------------------------------------------------------
def get_db_secret():
    """Fetch DB credentials from AWS Secrets Manager (cached per process)."""
    global _secret_cache
    if _secret_cache is None:
        client = boto3.client("secretsmanager", region_name=REGION)
        response = client.get_secret_value(SecretId=SECRET_ARN)
        _secret_cache = json.loads(response["SecretString"])
    return _secret_cache


def get_connection():
    secret = get_db_secret()
    ssl = {"ca": CA_BUNDLE} if os.path.exists(CA_BUNDLE) else None
    conn = pymysql.connect(
        host=secret["host"],
        port=int(secret["port"]),
        user=secret["username"],
        password=secret["password"],
        database=secret["dbname"],
        connect_timeout=3,
        ssl=ssl,
        cursorclass=pymysql.cursors.DictCursor,
        charset="utf8mb4",
    )
    ensure_schema(conn)
    return conn


def ensure_schema(conn):
    global _schema_ready
    if _schema_ready:
        return
    with conn.cursor() as cur:
        cur.execute(
            "CREATE TABLE IF NOT EXISTS visits ("
            " id INT AUTO_INCREMENT PRIMARY KEY,"
            " instance_id VARCHAR(64),"
            " visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
        )
        cur.execute(
            "CREATE TABLE IF NOT EXISTS submissions ("
            " id INT AUTO_INCREMENT PRIMARY KEY,"
            " name VARCHAR(100) NOT NULL,"
            " email VARCHAR(255) NOT NULL,"
            " category VARCHAR(30) NOT NULL,"
            " message TEXT NOT NULL,"
            " instance_id VARCHAR(64),"
            " az VARCHAR(32),"
            " created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
            " INDEX idx_created (created_at)"
            ") CHARACTER SET utf8mb4"
        )
    conn.commit()
    _schema_ready = True


def imds(path):
    """Read EC2 instance metadata using IMDSv2 (token required)."""
    try:
        token_req = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        )
        token = urllib.request.urlopen(token_req, timeout=1).read().decode()
        req = urllib.request.Request(
            f"http://169.254.169.254/latest/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token},
        )
        return urllib.request.urlopen(req, timeout=1).read().decode()
    except Exception:
        return "unknown"


def instance_meta():
    """Static instance metadata, cached for the life of the process."""
    if not _meta_cache:
        _meta_cache.update(
            instance_id=imds("instance-id"),
            az=imds("placement/availability-zone"),
            region=imds("placement/region"),
            instance_type=imds("instance-type"),
            private_ip=imds("local-ipv4"),
        )
    return _meta_cache


def uptime():
    seconds = int(time.time() - STARTED_AT)
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes = seconds // 60
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


# ---------------------------------------------------------------------------
# Sessions / CSRF
# ---------------------------------------------------------------------------
def session_secret_key():
    """Same key on every instance (derived from the DB secret) so sessions and
    CSRF tokens work no matter which instance the ALB picks."""
    for attempt in range(3):
        try:
            seed = get_db_secret()["password"]
            return hashlib.sha256(f"flask-session:{seed}".encode()).hexdigest()
        except Exception:
            if not SECRET_ARN:
                break
            time.sleep(2 * (attempt + 1))
    return secrets.token_hex(32)


def csrf_token():
    if "csrf" not in session:
        session["csrf"] = secrets.token_urlsafe(32)
    return session["csrf"]


app.jinja_env.globals.update(csrf_token=csrf_token, categories=CATEGORIES)


@app.context_processor
def inject_common():
    return {"meta": instance_meta(), "app_version": APP_VERSION}


# ---------------------------------------------------------------------------
# Data access
# ---------------------------------------------------------------------------
def dashboard_data():
    """Record a visit and gather DB stats; never raises."""
    meta = instance_meta()
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute("INSERT INTO visits (instance_id) VALUES (%s)", (meta["instance_id"],))
            cur.execute("SELECT COUNT(*) AS n FROM visits")
            visits = cur.fetchone()["n"]
            cur.execute("SELECT COUNT(*) AS n FROM submissions")
            total = cur.fetchone()["n"]
            cur.execute(
                "SELECT id, name, category, message, az, created_at FROM submissions"
                " ORDER BY id DESC LIMIT 5"
            )
            recent = cur.fetchall()
            cur.execute("SELECT VERSION() AS v")
            version = cur.fetchone()["v"]
        conn.commit()
        conn.close()
        return {"db_ok": True, "db_version": version, "visits": visits, "total": total, "recent": recent}
    except Exception as exc:
        return {"db_ok": False, "db_error": type(exc).__name__, "visits": None, "total": None, "recent": []}


def validate(form):
    data = {
        "name": form.get("name", "").strip(),
        "email": form.get("email", "").strip(),
        "category": form.get("category", "").strip(),
        "message": form.get("message", "").strip(),
    }
    errors = {}
    if not 1 <= len(data["name"]) <= 100:
        errors["name"] = "Enter your name (up to 100 characters)."
    if len(data["email"]) > 255 or not EMAIL_RE.match(data["email"]):
        errors["email"] = "Enter a valid email address."
    if data["category"] not in CATEGORIES:
        errors["category"] = "Choose a category."
    if not 1 <= len(data["message"]) <= 2000:
        errors["message"] = "Enter a message (up to 2000 characters)."
    return data, errors


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("index.html", form={}, errors={}, uptime=uptime(), **dashboard_data())


@app.route("/submit", methods=["POST"])
def submit():
    if not hmac.compare_digest(request.form.get("csrf_token", ""), session.get("csrf", "")):
        flash("Your session expired. Please submit the form again.", "error")
        return redirect(url_for("index") + "#form")

    data, errors = validate(request.form)
    if errors:
        return render_template("index.html", form=data, errors=errors, uptime=uptime(), **dashboard_data()), 400

    meta = instance_meta()
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO submissions (name, email, category, message, instance_id, az)"
                " VALUES (%s, %s, %s, %s, %s, %s)",
                (data["name"], data["email"], data["category"], data["message"], meta["instance_id"], meta["az"]),
            )
            new_id = cur.lastrowid
        conn.commit()
        conn.close()
    except Exception as exc:
        flash(f"Could not save your submission ({type(exc).__name__}). Please try again.", "error")
        return redirect(url_for("index") + "#form")

    flash(f"Thanks {data['name']}! Submission #{new_id} was saved to RDS by {meta['instance_id']}.", "success")
    return redirect(url_for("submissions"))


@app.route("/submissions")
def submissions():
    q = request.args.get("q", "").strip()[:100]
    category = request.args.get("category", "")
    category = category if category in CATEGORIES else ""
    try:
        page = max(1, int(request.args.get("page", 1)))
    except ValueError:
        page = 1

    where, params = [], []
    if q:
        where.append("(name LIKE %s OR message LIKE %s OR email LIKE %s)")
        like = f"%{q}%"
        params += [like, like, like]
    if category:
        where.append("category = %s")
        params.append(category)
    where_sql = (" WHERE " + " AND ".join(where)) if where else ""

    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) AS n FROM submissions{where_sql}", params)
            total = cur.fetchone()["n"]
            pages = max(1, math.ceil(total / PAGE_SIZE))
            page = min(page, pages)
            cur.execute(
                "SELECT id, name, email, category, message, instance_id, az, created_at"
                f" FROM submissions{where_sql} ORDER BY id DESC LIMIT %s OFFSET %s",
                params + [PAGE_SIZE, (page - 1) * PAGE_SIZE],
            )
            rows = cur.fetchall()
        conn.close()
        db_error = None
    except Exception as exc:
        rows, total, pages, db_error = [], 0, 1, type(exc).__name__

    return render_template(
        "submissions.html",
        rows=rows, total=total, page=page, pages=pages,
        q=q, category=category, db_error=db_error,
    )


@app.route("/api/submissions")
def api_submissions():
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, category, message, az, created_at"
                " FROM submissions ORDER BY id DESC LIMIT 50"
            )
            rows = cur.fetchall()
        conn.close()
    except Exception as exc:
        return jsonify(error=type(exc).__name__), 503
    for r in rows:
        r["created_at"] = r["created_at"].isoformat() + "Z"
    return jsonify(count=len(rows), served_by=instance_meta()["instance_id"], submissions=rows)


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


@app.route("/db-health")
def db_health():
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        return jsonify(database="ok"), 200
    except Exception as exc:
        return jsonify(database="error", error=type(exc).__name__), 503


app.secret_key = session_secret_key()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

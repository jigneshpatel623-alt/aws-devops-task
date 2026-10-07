"""Demo web application for the AWS DevOps practical task.

- "/"        : shows which EC2 instance / AZ served the request and the DB status
- "/health"  : lightweight liveness check used by the ALB target group
- "/db-health": checks connectivity to RDS MySQL (credentials from Secrets Manager)
"""
import json
import os
import urllib.request

import boto3
import pymysql
from flask import Flask, jsonify, render_template

app = Flask(__name__)

REGION = os.environ.get("AWS_REGION", "ap-south-1")
SECRET_ARN = os.environ.get("DB_SECRET_ARN", "")
CA_BUNDLE = os.environ.get("DB_CA_BUNDLE", "/opt/webapp/rds-ca-bundle.pem")

_secret_cache = None


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
    return pymysql.connect(
        host=secret["host"],
        port=int(secret["port"]),
        user=secret["username"],
        password=secret["password"],
        database=secret["dbname"],
        connect_timeout=3,
        ssl=ssl,
    )


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


def record_visit():
    """Insert a visit row and return (ok, mysql_version, total_visits or error)."""
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute(
                "CREATE TABLE IF NOT EXISTS visits ("
                " id INT AUTO_INCREMENT PRIMARY KEY,"
                " instance_id VARCHAR(64),"
                " visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
            )
            cur.execute("INSERT INTO visits (instance_id) VALUES (%s)", (imds("instance-id"),))
            cur.execute("SELECT COUNT(*) FROM visits")
            total = cur.fetchone()[0]
            cur.execute("SELECT VERSION()")
            version = cur.fetchone()[0]
        conn.commit()
        conn.close()
        return True, version, total
    except Exception as exc:
        return False, None, type(exc).__name__


@app.route("/")
def index():
    db_ok, db_version, visits = record_visit()
    return render_template(
        "index.html",
        instance_id=imds("instance-id"),
        az=imds("placement/availability-zone"),
        db_ok=db_ok,
        db_version=db_version,
        visits=visits,
    )


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


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

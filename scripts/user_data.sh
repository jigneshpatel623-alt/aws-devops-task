#!/bin/bash
# EC2 bootstrap script - rendered by Terraform templatefile().
# Terraform variables: region, app_bucket, secret_arn, app_version
# App version: ${app_version}
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

APP_DIR=/opt/webapp

# 1. Packages
dnf install -y python3 python3-pip

# 2. Application code from the private S3 app bucket
mkdir -p "$APP_DIR"
aws s3 cp "s3://${app_bucket}/app/" "$APP_DIR/" --recursive --region "${region}"

# 3. RDS CA bundle for TLS connections to MySQL
curl -fsSL -o "$APP_DIR/rds-ca-bundle.pem" https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# 4. Python virtualenv + dependencies
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"

# 5. Unprivileged service user
id webapp || useradd --system --no-create-home --shell /sbin/nologin webapp
chown -R webapp:webapp "$APP_DIR"

# 6. systemd service (gunicorn on port 8080)
cat > /etc/systemd/system/webapp.service <<'EOF'
[Unit]
Description=Flask web application
After=network-online.target
Wants=network-online.target

[Service]
User=webapp
Group=webapp
WorkingDirectory=/opt/webapp
Environment=AWS_REGION=${region}
Environment=DB_SECRET_ARN=${secret_arn}
Environment=DB_CA_BUNDLE=/opt/webapp/rds-ca-bundle.pem
Environment=APP_VERSION=${app_version}
ExecStart=/opt/webapp/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:8080 --access-logfile - app:app
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now webapp

# 7. Local check
sleep 3
curl -fsS http://localhost:8080/health

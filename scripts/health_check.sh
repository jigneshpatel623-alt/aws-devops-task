#!/bin/bash
# End-to-end validation of the deployed application.
# Usage: ./scripts/health_check.sh https://app.example.com
set -uo pipefail

URL="${1:?Usage: $0 <https-app-url>}"
HOST="${URL#https://}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"
SLEEP_SECONDS="${SLEEP_SECONDS:-20}"

# Self-signed mode (no domain): the URL is the ALB DNS name and the cert is not publicly trusted
K=""
case "$HOST" in
  *.elb.amazonaws.com*) K="-k"; echo "Self-signed certificate mode: skipping trust verification" ;;
esac
curl() { command curl $K "$@"; }

echo "==> Waiting for $URL/health to return 200"
for i in $(seq 1 "$MAX_ATTEMPTS"); do
  if curl -fsS --max-time 10 "$URL/health"; then
    echo
    echo "Health check passed (attempt $i)"
    break
  fi
  if [ "$i" -eq "$MAX_ATTEMPTS" ]; then
    echo "Health check FAILED after $MAX_ATTEMPTS attempts"
    exit 1
  fi
  echo "Attempt $i failed, retrying in $SLEEP_SECONDS s..."
  sleep "$SLEEP_SECONDS"
done

echo "==> Checking database connectivity"
curl -fsS --max-time 10 "$URL/db-health" || { echo "DB health check FAILED"; exit 1; }
echo

echo "==> Checking HTTP -> HTTPS redirect"
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$HOST/")
if [ "$CODE" != "301" ]; then
  echo "Expected 301 redirect from HTTP, got $CODE"
  exit 1
fi
echo "HTTP redirects to HTTPS (301)"

echo "==> Checking TLS certificate"
curl -sS --max-time 10 -o /dev/null -w "TLS OK, HTTP %{http_code}\n" "$URL/" || exit 1

echo "All checks passed."

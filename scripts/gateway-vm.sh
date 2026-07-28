#!/bin/bash
# Provisions the api-gateway-app on gateway-vm. No database here by design.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
APP_DIR="/vagrant/srcs/api-gateway-app"

cd "$APP_DIR"
python3 -m venv venv
./venv/bin/pip install -q --upgrade pip
./venv/bin/pip install -q -r requirements.txt

cat > "$APP_DIR/.pm2.env" <<EOF
GATEWAY_APP_HOST=${GATEWAY_APP_HOST}
GATEWAY_APP_PORT=${GATEWAY_APP_PORT}
INVENTORY_API_URL=${INVENTORY_API_URL}
RABBITMQ_HOST=${RABBITMQ_HOST}
RABBITMQ_PORT=${RABBITMQ_PORT}
RABBITMQ_USER=${RABBITMQ_USER}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
BILLING_QUEUE=${BILLING_QUEUE}
EOF

set -a
source "$APP_DIR/.pm2.env"
set +a

pm2 delete api-gateway-app 2>/dev/null || true
pm2 start "$APP_DIR/venv/bin/python" --name api-gateway-app --cwd "$APP_DIR" -- "$APP_DIR/server.py"
pm2 save
env PATH="$PATH:/usr/bin" pm2 startup systemd -u root --hp /root >/dev/null || true

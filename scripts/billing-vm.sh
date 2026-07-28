#!/bin/bash
# Provisions PostgreSQL + RabbitMQ + the billing-app consumer on billing-vm.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
APP_DIR="/vagrant/srcs/billing-app"

apt-get install -y -qq postgresql postgresql-contrib rabbitmq-server
systemctl enable postgresql rabbitmq-server
systemctl start postgresql rabbitmq-server

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${BILLING_DB_USER}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE ROLE ${BILLING_DB_USER} LOGIN PASSWORD '${BILLING_DB_PASSWORD}';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${BILLING_DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${BILLING_DB_NAME} OWNER ${BILLING_DB_USER};"

# RabbitMQ user matching RABBITMQ_USER/PASSWORD (guest is loopback-only by default).
if [ "${RABBITMQ_USER}" != "guest" ]; then
    rabbitmqctl user_exists "${RABBITMQ_USER}" || rabbitmqctl add_user "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}"
    rabbitmqctl set_user_tags "${RABBITMQ_USER}" administrator
    rabbitmqctl set_permissions -p / "${RABBITMQ_USER}" ".*" ".*" ".*"
else
    rabbitmqctl set_permissions -p / guest ".*" ".*" ".*"
fi

cd "$APP_DIR"
python3 -m venv venv
./venv/bin/pip install -q --upgrade pip
./venv/bin/pip install -q -r requirements.txt

cat > "$APP_DIR/.pm2.env" <<EOF
BILLING_DB_HOST=${BILLING_DB_HOST}
BILLING_DB_PORT=${BILLING_DB_PORT}
BILLING_DB_NAME=${BILLING_DB_NAME}
BILLING_DB_USER=${BILLING_DB_USER}
BILLING_DB_PASSWORD=${BILLING_DB_PASSWORD}
RABBITMQ_HOST=${RABBITMQ_HOST}
RABBITMQ_PORT=${RABBITMQ_PORT}
RABBITMQ_USER=${RABBITMQ_USER}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
BILLING_QUEUE=${BILLING_QUEUE}
EOF

set -a
source "$APP_DIR/.pm2.env"
set +a

pm2 delete billing-app 2>/dev/null || true
pm2 start "$APP_DIR/venv/bin/python" --name billing-app --cwd "$APP_DIR" -- "$APP_DIR/server.py"
pm2 save
env PATH="$PATH:/usr/bin" pm2 startup systemd -u root --hp /root >/dev/null || true

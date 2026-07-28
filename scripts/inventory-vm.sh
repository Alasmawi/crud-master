#!/bin/bash
# Provisions PostgreSQL + the inventory-app on inventory-vm.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
APP_DIR="/vagrant/srcs/inventory-app"

apt-get install -y -qq postgresql postgresql-contrib
systemctl enable postgresql
systemctl start postgresql

# Create the DB role and database idempotently.
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${INVENTORY_DB_USER}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE ROLE ${INVENTORY_DB_USER} LOGIN PASSWORD '${INVENTORY_DB_PASSWORD}';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${INVENTORY_DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${INVENTORY_DB_NAME} OWNER ${INVENTORY_DB_USER};"

cd "$APP_DIR"
python3 -m venv venv
./venv/bin/pip install -q --upgrade pip
./venv/bin/pip install -q -r requirements.txt

cat > "$APP_DIR/.pm2.env" <<EOF
INVENTORY_DB_HOST=${INVENTORY_DB_HOST}
INVENTORY_DB_PORT=${INVENTORY_DB_PORT}
INVENTORY_DB_NAME=${INVENTORY_DB_NAME}
INVENTORY_DB_USER=${INVENTORY_DB_USER}
INVENTORY_DB_PASSWORD=${INVENTORY_DB_PASSWORD}
INVENTORY_APP_HOST=${INVENTORY_APP_HOST}
INVENTORY_APP_PORT=${INVENTORY_APP_PORT}
EOF

set -a
source "$APP_DIR/.pm2.env"
set +a

pm2 delete inventory-app 2>/dev/null || true
pm2 start "$APP_DIR/venv/bin/python" --name inventory-app --cwd "$APP_DIR" -- "$APP_DIR/server.py"
pm2 save
env PATH="$PATH:/usr/bin" pm2 startup systemd -u root --hp /root >/dev/null || true

#!/bin/bash
# Provisions inventory-vm: PostgreSQL (movies_db) + inventory-app.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq postgresql postgresql-contrib
systemctl enable --now postgresql

cd /tmp  # psql runs as postgres, which can't read the vagrant home dir

# Role and database, created idempotently. The `movies` table is created by
# the app on startup (SQLAlchemy create_all).
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${INVENTORY_DB_USER}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE ROLE ${INVENTORY_DB_USER} LOGIN PASSWORD '${INVENTORY_DB_PASSWORD}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${INVENTORY_DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${INVENTORY_DB_NAME} OWNER ${INVENTORY_DB_USER};"

bash /vagrant/scripts/deploy-app.sh inventory-app

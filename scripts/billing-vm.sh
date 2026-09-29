#!/bin/bash
# Provisions billing-vm: PostgreSQL (billing_db) + RabbitMQ + billing-app.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq postgresql postgresql-contrib rabbitmq-server
systemctl enable --now postgresql rabbitmq-server

cd /tmp  # psql runs as postgres, which can't read the vagrant home dir

# --- PostgreSQL: role and database. The `orders` table is created by the app.
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${BILLING_DB_USER}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE ROLE ${BILLING_DB_USER} LOGIN PASSWORD '${BILLING_DB_PASSWORD}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${BILLING_DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${BILLING_DB_NAME} OWNER ${BILLING_DB_USER};"

# --- RabbitMQ: management UI (port 15672) + rabbitmqadmin CLI, for publishing
# test messages to the queue by hand.
rabbitmq-plugins enable --quiet rabbitmq_management
systemctl restart rabbitmq-server
rabbitmqctl await_startup

# A non-guest user, since guest may only connect from localhost and the
# gateway connects from gateway-vm.
if ! rabbitmqctl list_users --quiet | awk '{print $1}' | grep -qx "${RABBITMQ_USER}"; then
    rabbitmqctl add_user "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}"
fi
rabbitmqctl set_user_tags "${RABBITMQ_USER}" administrator
rabbitmqctl set_permissions -p / "${RABBITMQ_USER}" ".*" ".*" ".*"

curl -fsS -o /usr/local/bin/rabbitmqadmin http://localhost:15672/cli/rabbitmqadmin
chmod +x /usr/local/bin/rabbitmqadmin

# Declare the queue up front so it exists before either app has started.
rabbitmqadmin -u "${RABBITMQ_USER}" -p "${RABBITMQ_PASSWORD}" \
    declare queue name="${BILLING_QUEUE}" durable=true

bash /vagrant/scripts/deploy-app.sh billing-app

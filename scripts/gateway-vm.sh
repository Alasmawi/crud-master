#!/bin/bash
# Provisions gateway-vm: only the api-gateway-app, no database.
set -euo pipefail

bash /vagrant/scripts/deploy-app.sh api-gateway-app

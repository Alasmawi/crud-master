#!/bin/bash
# Shared provisioning: Python, venv tooling, and PM2 (via Node.js) on every VM.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip curl gnupg ca-certificates

if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null
    apt-get install -y -qq nodejs
fi

if ! command -v pm2 >/dev/null 2>&1; then
    npm install -g pm2 --silent
fi

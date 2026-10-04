#!/bin/bash
# Usage: deploy-app.sh <app-dir-name> [pm2-name]
# Creates the app's venv, installs requirements, and (re)starts it under PM2.
# The venv lives on the VM's own disk (/opt/venvs): pip fails inside the
# VirtualBox shared folder (/vagrant).
# The app's settings must already be exported (Vagrant passes them via `env:`);
# PM2 captures them at start and `pm2 save` persists them across reboots.
set -euo pipefail

APP_DIR="/vagrant/srcs/$1"
VENV_DIR="/opt/venvs/$1"
APP_NAME="${2:-$1}"  # name shown in `pm2 list`

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q -r "$APP_DIR/requirements.txt"

pm2 delete "$APP_NAME" 2>/dev/null || true
pm2 start "$VENV_DIR/bin/python" --name "$APP_NAME" --cwd "$APP_DIR" \
    --restart-delay 3000 -- "$APP_DIR/server.py"
pm2 save
pm2 startup systemd -u root --hp /root >/dev/null

#!/usr/bin/env bash
set -euo pipefail

ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME:-Admin}"
ADMIN_LASTNAME="${ADMIN_LASTNAME:-User}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-Admin123!}"
SUPERSET_PORT="${SUPERSET_PORT:-8088}"
SUPERSET_HOME="${SUPERSET_HOME:-$HOME/.superset}"
VENV_PATH="${VENV_PATH:-$HOME/superset-venv}"
PYTHON_BIN="${PYTHON_BIN:-python3.11}"

echo "==> Update apt"
sudo apt-get update

echo "==> Install base packages"
sudo apt-get install -y software-properties-common curl wget git ca-certificates gnupg \
  apt-transport-https build-essential libssl-dev libffi-dev libsasl2-dev libldap2-dev \
  default-libmysqlclient-dev pkg-config

echo "==> Install Python 3.11 for Superset"
if ! command -v ${PYTHON_BIN} >/dev/null 2>&1; then
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get update
  sudo apt-get install -y python3.11 python3.11-dev python3.11-venv
fi

echo "==> Install ClickHouse repository"
if [ ! -f /usr/share/keyrings/clickhouse-keyring.gpg ]; then
  curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
fi

ARCH=$(dpkg --print-architecture)
echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg arch=${ARCH}] https://packages.clickhouse.com/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/clickhouse.list >/dev/null

echo "==> Install ClickHouse"
sudo apt-get update
sudo apt-get install -y clickhouse-server clickhouse-client

echo "==> Enable and start ClickHouse"
sudo systemctl enable clickhouse-server
sudo systemctl restart clickhouse-server

echo "==> Prepare Superset directories"
mkdir -p "${SUPERSET_HOME}"

echo "==> Create Python virtualenv"
if [ ! -d "${VENV_PATH}" ]; then
  ${PYTHON_BIN} -m venv "${VENV_PATH}"
fi

source "${VENV_PATH}/bin/activate"

echo "==> Upgrade pip tooling"
pip install --upgrade pip setuptools wheel

echo "==> Install Superset"
pip install apache-superset

echo "==> Reset Superset metadata DB"
rm -f "${SUPERSET_HOME}/superset.db"

echo "==> Create fresh Superset config"
SECRET_KEY=$(openssl rand -base64 42 | tr -d '\n')
cat > "${SUPERSET_HOME}/superset_config.py" <<EOF
SECRET_KEY = "${SECRET_KEY}"
SUPERSET_WEBSERVER_PORT = ${SUPERSET_PORT}
EOF

export SUPERSET_CONFIG_PATH="${SUPERSET_HOME}/superset_config.py"
export SUPERSET_SECRET_KEY="${SECRET_KEY}"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

echo "==> Initialize Superset DB"
superset db upgrade

echo "==> Create admin user"
if ! superset fab list-users 2>/dev/null | grep -q "${ADMIN_USERNAME}"; then
  superset fab create-admin \
    --username "${ADMIN_USERNAME}" \
    --firstname "${ADMIN_FIRSTNAME}" \
    --lastname "${ADMIN_LASTNAME}" \
    --email "${ADMIN_EMAIL}" \
    --password "${ADMIN_PASSWORD}"
else
  echo "Admin user ${ADMIN_USERNAME} already exists, skipping"
fi

echo "==> Run superset init"
superset init

echo "==> Create systemd service for Superset"
sudo tee /etc/systemd/system/superset.service >/dev/null <<EOF
[Unit]
Description=Apache Superset
After=network.target clickhouse-server.service

[Service]
Type=simple
User=${USER}
WorkingDirectory=${HOME}
Environment=SUPERSET_CONFIG_PATH=${SUPERSET_HOME}/superset_config.py
Environment=SUPERSET_SECRET_KEY=${SECRET_KEY}
Environment=LANG=C.UTF-8
Environment=LC_ALL=C.UTF-8
ExecStart=${VENV_PATH}/bin/superset run -p ${SUPERSET_PORT} --host 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Enable and start Superset service"
sudo systemctl daemon-reload
sudo systemctl enable superset
sudo systemctl restart superset

echo "==> Done"
echo "ClickHouse status:"
sudo systemctl --no-pager --full status clickhouse-server | head -n 20 || true
echo
echo "Superset status:"
sudo systemctl --no-pager --full status superset | head -n 20 || true
echo
echo "Superset URL: http://$(curl -s ifconfig.me):${SUPERSET_PORT}"
echo "Admin login: ${ADMIN_USERNAME}"
echo "Admin password: ${ADMIN_PASSWORD}"

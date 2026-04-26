param(
    [string]$HostIp = "81.26.191.142",
    [string]$User = "otus",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
    [string]$RemoteScriptPath = "/home/otus/install_clickhouse_superset.sh",
    [string]$AdminUsername = "admin",
    [string]$AdminPassword = "Admin123!",
    [string]$AdminEmail = "admin@example.com",
    [int]$SupersetPort = 8088
)

$ErrorActionPreference = "Stop"
$LocalScript = Join-Path $env:TEMP "install_clickhouse_superset.sh"

$BashScript = @"
#!/usr/bin/env bash
set -euo pipefail

ADMIN_USERNAME="${AdminUsername}"
ADMIN_FIRSTNAME="Admin"
ADMIN_LASTNAME="User"
ADMIN_EMAIL="${AdminEmail}"
ADMIN_PASSWORD="${AdminPassword}"
SUPERSET_PORT="${SupersetPort}"
SUPERSET_HOME="\$HOME/.superset"
VENV_PATH="\$HOME/superset-venv"
PYTHON_BIN="python3.11"

echo "==> Update apt"
sudo apt-get update

echo "==> Install base packages"
sudo apt-get install -y software-properties-common curl wget git ca-certificates gnupg \
  apt-transport-https build-essential libssl-dev libffi-dev libsasl2-dev libldap2-dev \
  default-libmysqlclient-dev pkg-config

echo "==> Install Python 3.11"
if ! command -v \$PYTHON_BIN >/dev/null 2>&1; then
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get update
  sudo apt-get install -y python3.11 python3.11-dev python3.11-venv
fi

echo "==> Install ClickHouse repo"
if [ ! -f /usr/share/keyrings/clickhouse-keyring.gpg ]; then
  curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
fi

ARCH=\$(dpkg --print-architecture)
echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg arch=\${ARCH}] https://packages.clickhouse.com/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/clickhouse.list >/dev/null

echo "==> Install ClickHouse"
sudo apt-get update
sudo apt-get install -y clickhouse-server clickhouse-client
sudo systemctl enable clickhouse-server
sudo systemctl restart clickhouse-server

echo "==> Prepare Superset"
mkdir -p "\$SUPERSET_HOME"

if [ ! -d "\$VENV_PATH" ]; then
  \$PYTHON_BIN -m venv "\$VENV_PATH"
fi

source "\$VENV_PATH/bin/activate"

echo "==> Upgrade pip"
pip install --upgrade pip setuptools wheel

echo "==> Install Superset and ClickHouse driver"
pip install apache-superset clickhouse-connect

echo "==> Reset Superset metadata DB"
rm -f "\$SUPERSET_HOME/superset.db"

SECRET_KEY=\$(openssl rand -base64 42 | tr -d '\n')
cat > "\$SUPERSET_HOME/superset_config.py" <<EOF
SECRET_KEY = "\$SECRET_KEY"
SUPERSET_WEBSERVER_PORT = \$SUPERSET_PORT
EOF

export SUPERSET_CONFIG_PATH="\$SUPERSET_HOME/superset_config.py"
export SUPERSET_SECRET_KEY="\$SECRET_KEY"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

echo "==> Init Superset DB"
superset db upgrade

echo "==> Create admin"
superset fab create-admin \
  --username "\$ADMIN_USERNAME" \
  --firstname "\$ADMIN_FIRSTNAME" \
  --lastname "\$ADMIN_LASTNAME" \
  --email "\$ADMIN_EMAIL" \
  --password "\$ADMIN_PASSWORD"

echo "==> Superset init"
superset init

echo "==> Create systemd service"
sudo tee /etc/systemd/system/superset.service >/dev/null <<SERVICEEOF
[Unit]
Description=Apache Superset
After=network.target clickhouse-server.service

[Service]
Type=simple
User=$User
WorkingDirectory=/home/$User
Environment=SUPERSET_CONFIG_PATH=/home/$User/.superset/superset_config.py
Environment=SUPERSET_SECRET_KEY=\$SECRET_KEY
Environment=LANG=C.UTF-8
Environment=LC_ALL=C.UTF-8
ExecStart=/home/$User/superset-venv/bin/superset run -p \$SUPERSET_PORT --host 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

echo "==> Reload systemd and start Superset"
sudo systemctl daemon-reload
sudo systemctl enable superset
sudo systemctl restart superset

echo "==> Check services"
sudo systemctl --no-pager --full status clickhouse-server | head -n 20 || true
echo
sudo systemctl --no-pager --full status superset | head -n 20 || true
echo
clickhouse-client -q "SELECT version()" || true
curl -I http://127.0.0.1:\$SUPERSET_PORT/login/ || true

echo
echo "=== DONE ==="
echo "Superset URL: http://$HostIp:\$SUPERSET_PORT"
echo "Admin username: \$ADMIN_USERNAME"
echo "Admin password: \$ADMIN_PASSWORD"
echo
echo "ClickHouse connection URI for Superset:"
echo "clickhousedb://default:@localhost:8123/default"
"@

Set-Content -Path $LocalScript -Value $BashScript -Encoding UTF8

Write-Host "Copying script to VM..." -ForegroundColor Cyan
scp -i $KeyPath $LocalScript "${User}@${HostIp}:${RemoteScriptPath}"

Write-Host "Running script on VM..." -ForegroundColor Cyan
ssh -i $KeyPath "${User}@${HostIp}" "chmod +x ${RemoteScriptPath} && bash ${RemoteScriptPath}"

Write-Host ""
Write-Host "Done. Open: http://${HostIp}:${SupersetPort}" -ForegroundColor Green
Write-Host "Login: $AdminUsername" -ForegroundColor Green
Write-Host "Password: $AdminPassword" -ForegroundColor Green
Write-Host ""
Write-Host "Superset ClickHouse URI:" -ForegroundColor Yellow
Write-Host "clickhousedb://default:@localhost:8123/default" -ForegroundColor Yellow

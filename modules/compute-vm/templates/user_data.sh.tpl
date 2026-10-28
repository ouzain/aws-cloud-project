#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/vitalora-userdata.log) 2>&1

# --- Node.js (Amazon Linux 2023 fournit nodejs/npm directement) ------------
dnf install -y nodejs npm

mkdir -p /opt/vitalora
cd /opt/vitalora

cat > package.json <<'PKG_EOF'
${package_json}
PKG_EOF

cat > server.js <<'SERVER_EOF'
${server_js}
SERVER_EOF

# Front statique servi par express.static (compressé pour rester sous 16 Ko de user_data)
mkdir -p public
echo '${index_html_gz}' | base64 -d | gunzip > public/index.html
echo '${app_js_gz}' | base64 -d | gunzip > public/app.js
echo '${style_css_gz}' | base64 -d | gunzip > public/style.css

npm install --omit=dev

# --- Secret récupéré via SSM Parameter Store, jamais en dur ----------------
DB_PASSWORD=$(aws ssm get-parameter \
  --name "${db_password_ssm_name}" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region ${aws_region})

cat > /opt/vitalora/.env <<ENV_EOF
PORT=3000
DB_HOST=${db_host}
DB_PORT=3306
DB_NAME=${db_name}
DB_USER=${db_username}
DB_PASSWORD=$${DB_PASSWORD}
ASSETS_BUCKET=${assets_bucket}
AWS_REGION=${aws_region}
ENV_EOF
chmod 600 /opt/vitalora/.env
chown ec2-user:ec2-user /opt/vitalora -R

# --- Service systemd : démarre au boot, relance auto si crash --------------
cat > /etc/systemd/system/vitalora.service <<'UNIT_EOF'
[Unit]
Description=VITALORA web app
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/vitalora
EnvironmentFile=/opt/vitalora/.env
ExecStart=/usr/bin/node /opt/vitalora/server.js
Restart=always
RestartSec=5
User=ec2-user

[Install]
WantedBy=multi-user.target
UNIT_EOF

systemctl daemon-reload
systemctl enable vitalora
systemctl start vitalora

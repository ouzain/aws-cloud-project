#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/vitalora-userdata.log) 2>&1
# Les dépendances sont préparées localement. Seul Node.js est installé au démarrage.
dnf install -y nodejs22 unzip amazon-cloudwatch-agent
mkdir -p /opt/vitalora /var/log/vitalora
aws s3 cp "s3://${assets_bucket}/${application_key}" /tmp/vitalora-runtime.zip --region "${aws_region}"
unzip -q /tmp/vitalora-runtime.zip -d /opt/vitalora
DB_PASSWORD=$(aws ssm get-parameter --name "${db_password_ssm_name}" --with-decryption --query Parameter.Value --output text --region "${aws_region}")
cat > /opt/vitalora/.env <<ENV_EOF
PORT=3000
NODE_ENV=production
DB_HOST=${db_host}
DB_PORT=3306
DB_NAME=${db_name}
DB_USER=${db_username}
DB_PASSWORD=$${DB_PASSWORD}
DB_TLS=true
ASSETS_BUCKET=${assets_bucket}
AWS_REGION=${aws_region}
ORDER_TOPIC_ARN=${order_topic_arn}
ENV_EOF
chmod 600 /opt/vitalora/.env
chown -R ec2-user:ec2-user /opt/vitalora /var/log/vitalora
cat > /etc/systemd/system/vitalora.service <<'UNIT_EOF'
[Unit]
Description=VITALORA application and durable event publisher
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
WorkingDirectory=/opt/vitalora
EnvironmentFile=/opt/vitalora/.env
ExecStart=/usr/bin/node-22 /opt/vitalora/app/server.js
Restart=always
RestartSec=5
User=ec2-user
StandardOutput=append:/var/log/vitalora/application.log
StandardError=append:/var/log/vitalora/application.log
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
UNIT_EOF
cat > /opt/aws/amazon-cloudwatch-agent/etc/vitalora.json <<'LOG_EOF'
{"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/var/log/vitalora/application.log","log_group_name":"${application_log_group}","log_stream_name":"{instance_id}"}]}}}}
LOG_EOF
systemctl daemon-reload
systemctl enable --now vitalora
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/vitalora.json -s

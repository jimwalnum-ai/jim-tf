#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

ARCH="arm64"
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# ── packages ──────────────────────────────────────────────────────────
dnf install -y docker unzip
systemctl enable docker && systemctl start docker

# ── CNI plugins ───────────────────────────────────────────────────────
mkdir -p /opt/cni/bin
curl -sL "https://github.com/containernetworking/plugins/releases/download/v${cni_plugins_version}/cni-plugins-linux-$ARCH-v${cni_plugins_version}.tgz" \
  | tar -xz -C /opt/cni/bin

# ── Consul ────────────────────────────────────────────────────────────
curl -sL "https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_$ARCH.zip" -o /tmp/consul.zip
unzip -o /tmp/consul.zip -d /usr/local/bin && rm /tmp/consul.zip
chmod +x /usr/local/bin/consul

useradd --system --home /etc/consul.d --shell /bin/false consul || true
mkdir -p /opt/consul/data /etc/consul.d
chown -R consul:consul /opt/consul /etc/consul.d

cat > /etc/consul.d/consul.hcl <<'CONSULEOF'
datacenter = "${datacenter}"
data_dir   = "/opt/consul/data"
server     = true
bootstrap_expect = ${server_count}
bind_addr  = "{{ GetPrivateInterfaces | attr \"address\" }}"
client_addr = "0.0.0.0"
ui_config { enabled = true }

addresses {
  http = "0.0.0.0"
}

retry_join = ["provider=aws tag_key=${cluster_tag_key} tag_value=${cluster_tag_value}"]
CONSULEOF

cat > /etc/systemd/system/consul.service <<'SVCEOF'
[Unit]
Description=Consul
After=network-online.target
Wants=network-online.target

[Service]
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl enable consul && systemctl start consul

# ── Nomad ─────────────────────────────────────────────────────────────
curl -sL "https://releases.hashicorp.com/nomad/${nomad_version}/nomad_${nomad_version}_linux_$ARCH.zip" -o /tmp/nomad.zip
unzip -o /tmp/nomad.zip -d /usr/local/bin && rm /tmp/nomad.zip
chmod +x /usr/local/bin/nomad

useradd --system --home /etc/nomad.d --shell /bin/false nomad || true
mkdir -p /opt/nomad/data /etc/nomad.d
chown -R nomad:nomad /opt/nomad /etc/nomad.d

cat > /etc/nomad.d/nomad.hcl <<NOMADEOF
datacenter = "${datacenter}"
region     = "${region}"
data_dir   = "/opt/nomad/data"

bind_addr = "0.0.0.0"

advertise {
  http = "$PRIVATE_IP"
  rpc  = "$PRIVATE_IP"
  serf = "$PRIVATE_IP"
}

server {
  enabled          = true
  bootstrap_expect = ${server_count}
}

consul {
  address = "127.0.0.1:8500"
  auto_advertise       = true
  server_auto_join     = true
  client_auto_join     = true
  server_service_name  = "nomad"
  client_service_name  = "nomad-client"
}
NOMADEOF

cat > /etc/systemd/system/nomad.service <<'SVCEOF'
[Unit]
Description=Nomad
After=network-online.target consul.service
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl enable nomad && systemctl start nomad

echo "=== Nomad server bootstrap complete ==="

#!/usr/bin/env bash
set -Eeuo pipefail

VERSION=1.12.1
SHA256=b51d8a76aa2a9156a55d501aca6276fae09e262259a5e4e831d2c2222f084e63
PROMETHEUS_IP=192.168.77.20
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

if [[ $(uname -m) != x86_64 ]]; then
  echo "Only x86_64 is supported by this template" >&2
  exit 1
fi

dnf install -y curl tar
id node_exporter >/dev/null 2>&1 ||
  useradd --system --no-create-home --shell /sbin/nologin node_exporter

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
archive=node_exporter-${VERSION}.linux-amd64.tar.gz
url=https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/${archive}

curl --proto '=https' --tlsv1.2 -fsSLo "${workdir}/${archive}" "$url"
printf '%s  %s\n' "$SHA256" "${workdir}/${archive}" | sha256sum -c -
tar -xzf "${workdir}/${archive}" -C "$workdir"
install -o root -g root -m 0755 \
  "${workdir}/node_exporter-${VERSION}.linux-amd64/node_exporter" \
  /usr/local/bin/node_exporter
install -o root -g root -m 0644 \
  "${SCRIPT_DIR}/node_exporter.service" \
  /etc/systemd/system/node_exporter.service

if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${PROMETHEUS_IP}/32 port port=9100 protocol=tcp accept"
  firewall-cmd --reload
fi

systemctl daemon-reload
systemctl enable --now node_exporter
curl -fsS http://127.0.0.1:9100/metrics >/dev/null
systemctl --no-pager --full status node_exporter

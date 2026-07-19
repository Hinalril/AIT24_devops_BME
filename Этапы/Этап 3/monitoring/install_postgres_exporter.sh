#!/usr/bin/env bash
set -Eeuo pipefail

VERSION=0.20.1
SHA256=89d4f7e7920cad48fdc3133f789556ef5253c330a9f5fdace3bdb6344c0a8b5a
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
id postgres_exporter >/dev/null 2>&1 ||
  useradd --system --no-create-home --shell /sbin/nologin postgres_exporter

install -d -o root -g postgres_exporter -m 0750 /etc/postgres_exporter
if [[ ! -e /etc/postgres_exporter/postgres_exporter.env ]]; then
  install -o root -g postgres_exporter -m 0640 \
    "${SCRIPT_DIR}/postgres_exporter.env.example" \
    /etc/postgres_exporter/postgres_exporter.env
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
archive=postgres_exporter-${VERSION}.linux-amd64.tar.gz
url=https://github.com/prometheus-community/postgres_exporter/releases/download/v${VERSION}/${archive}

curl --proto '=https' --tlsv1.2 -fsSLo "${workdir}/${archive}" "$url"
printf '%s  %s\n' "$SHA256" "${workdir}/${archive}" | sha256sum -c -
tar -xzf "${workdir}/${archive}" -C "$workdir"
install -o root -g root -m 0755 \
  "${workdir}/postgres_exporter-${VERSION}.linux-amd64/postgres_exporter" \
  /usr/local/bin/postgres_exporter
install -o root -g root -m 0644 \
  "${SCRIPT_DIR}/postgres_exporter.service" \
  /etc/systemd/system/postgres_exporter.service

if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${PROMETHEUS_IP}/32 port port=9187 protocol=tcp accept"
  firewall-cmd --reload
fi

systemctl daemon-reload

if [[ -s /etc/postgres_exporter/password ]]; then
  chown postgres_exporter:postgres_exporter /etc/postgres_exporter/password
  chmod 0600 /etc/postgres_exporter/password
  systemctl enable --now postgres_exporter
  curl -fsS http://127.0.0.1:9187/metrics >/dev/null
  systemctl --no-pager --full status postgres_exporter
else
  echo "Installed. Create /etc/postgres_exporter/password, then run:"
  echo "systemctl enable --now postgres_exporter"
fi

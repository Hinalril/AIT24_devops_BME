#!/usr/bin/env bash
set -Eeuo pipefail

VERSION=3.13.1
SHA256=962b812371aff838d152b6ff2d56fdb7a6396f5542f48ebf73421b9721f0d103
LAB_NETWORK=192.168.77.0/24
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
id prometheus >/dev/null 2>&1 ||
  useradd --system --no-create-home --shell /sbin/nologin prometheus

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
archive=prometheus-${VERSION}.linux-amd64.tar.gz
url=https://github.com/prometheus/prometheus/releases/download/v${VERSION}/${archive}

curl --proto '=https' --tlsv1.2 -fsSLo "${workdir}/${archive}" "$url"
printf '%s  %s\n' "$SHA256" "${workdir}/${archive}" | sha256sum -c -
tar -xzf "${workdir}/${archive}" -C "$workdir"

install -o root -g root -m 0755 \
  "${workdir}/prometheus-${VERSION}.linux-amd64/prometheus" \
  /usr/local/bin/prometheus
install -o root -g root -m 0755 \
  "${workdir}/prometheus-${VERSION}.linux-amd64/promtool" \
  /usr/local/bin/promtool
install -d -o root -g prometheus -m 0750 /etc/prometheus
install -d -o prometheus -g prometheus -m 0750 /var/lib/prometheus
install -o root -g prometheus -m 0640 \
  "${SCRIPT_DIR}/prometheus.yml" \
  /etc/prometheus/prometheus.yml
install -o root -g root -m 0644 \
  "${SCRIPT_DIR}/prometheus.service" \
  /etc/systemd/system/prometheus.service

/usr/local/bin/promtool check config /etc/prometheus/prometheus.yml

if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${LAB_NETWORK} port port=9090 protocol=tcp accept"
  firewall-cmd --reload
fi

systemctl daemon-reload
systemctl enable --now prometheus
curl -fsS http://127.0.0.1:9090/-/ready
systemctl --no-pager --full status prometheus

#!/usr/bin/env bash
set -uo pipefail

for command_name in nmap nc; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing command: $command_name" >&2
    exit 2
  fi
done

failures=0

check_open() {
  local host=$1
  local port=$2
  local label=$3

  if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
    printf 'OK     %-18s %s:%s\n' "$label" "$host" "$port"
  else
    printf 'FAILED %-18s %s:%s\n' "$label" "$host" "$port"
    failures=$((failures + 1))
  fi
}

check_closed() {
  local host=$1
  local port=$2
  local label=$3

  if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
    printf 'FAILED %-18s %s:%s unexpectedly open\n' "$label" "$host" "$port"
    failures=$((failures + 1))
  else
    printf 'OK     %-18s %s:%s closed externally\n' "$label" "$host" "$port"
  fi
}

echo "Host discovery"
nmap -sn 192.168.77.0/24

echo
echo "Required TCP ports"
check_open 192.168.77.10 5432 "VIP PostgreSQL"
check_open 192.168.77.10 6432 "VIP PgBouncer"

for host in 192.168.77.11 192.168.77.12 192.168.77.13; do
  check_open "$host" 22 "SSH"
  check_open "$host" 2379 "ETCD client"
  check_open "$host" 2380 "ETCD peer"
  check_open "$host" 5432 "PostgreSQL"
  check_open "$host" 6432 "PgBouncer"
  check_open "$host" 8008 "Patroni REST"
  check_open "$host" 9100 "Node Exporter"
  check_open "$host" 9187 "Postgres Exporter"
  check_open "$host" 10050 "Zabbix Agent"
done

check_open 192.168.77.20 22 "SSH"
check_open 192.168.77.20 80 "pgAdmin Nginx"
check_open 192.168.77.20 3000 "Grafana"
check_open 192.168.77.20 8080 "Zabbix Web"
check_open 192.168.77.20 9090 "Prometheus"
check_open 192.168.77.20 9100 "Node Exporter"
check_open 192.168.77.20 10050 "Zabbix Agent"
check_open 192.168.77.20 10051 "Zabbix Server"
check_closed 192.168.77.20 5050 "pgAdmin container"

echo
if ((failures > 0)); then
  echo "Checks failed: $failures" >&2
  exit 1
fi

echo "All expected TCP checks passed"

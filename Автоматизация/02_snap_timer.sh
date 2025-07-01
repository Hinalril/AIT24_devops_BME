#!/usr/bin/env bash
#
# snap_timer.sh
#   AIT24_devops_BME/Автоматизация/02_snapshot_setup.sh   – уже должен существовать!
#
# Таймер: первый запуск через 10 мин после старта системы,
#         далее каждые 1 минуту

set -e

#──────────────────────────
# Шаг 1. Файлы сервиса и таймера
#──────────────────────────
SERVICE_FILE="/etc/systemd/system/pg_lv_snapshot.service"
TIMER_FILE="/etc/systemd/system/pg_lv_snapshot.timer"


#──────────────────────────
# Шаг 2. Допишем в конец SERVICE_FILE
#──────────────────────────
echo "→ Пишем $SERVICE_FILE"
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Create LVM snapshot of /dev/ol/pglv

[Service]
Type=oneshot
ExecStart=AIT24_devops_BME/Автоматизация/02_snapshot_setup.sh
EOF

#──────────────────────────
# Шаг 3. Допишем в конец TIMER_FILE
#──────────────────────────
echo "→ Пишем $TIMER_FILE"
cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=Take /dev/ol/pglv snapshot every 2 hours (simple loop)

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

#──────────────────────────
# Шаг 4. Перезапуск конфигурации и запуск таймера
#──────────────────────────
echo "Перезагружаем конфигурацию systemd"
systemctl daemon-reload

echo "Включаем и запускаем таймер"
systemctl enable --now pg_lv_snapshot.timer

echo "Готово!  Проверьте расписание:"
systemctl list-timers pg_lv_snapshot.timer

#!/usr/bin/env bash
#
# 05_init_sql.sh - автоматизация задания №5 (Инициализация и настройка PostgreSQL)
#   1. создать базу данных PostgreSQL;
#   2. инициализировать кластер с включёнными контрольными суммами;
#   3. настроить удалённое подключение (поправить файлы postgresql.conf, pg_hba.conf);
#
# # Запускать от root:  sudo ./05_init_sql.sh

set -e

# ──────────────────────────────
# Шаг 0. Требования запустить от root
# ──────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт от root!"
  exit 1
fi

# ──────────────────────────────
# Шаг 1. Переменные окружения
# ──────────────────────────────
PG_VERSION="15"                                # версия PostgreSQL
PG_USER="postgres"                             # системный пользователь
                                               # имя, под которым работает служба PostgreSQL
PG_DATA="/var/lib/pgsql/data"    # каталог кластера, где PostgreSQL хранит данные
PG_DELETE_BACKUP=7                             # удалить бэкапы старше N дней


# ──────────────────────────────
# Шаг 2. Поиск initdb и имени службы
# ──────────────────────────────
if command -v initdb &>/dev/null; then
  PG_BIN="$(dirname "$(command -v initdb)")"
else
  # пробуем типичный путь PGDG
  PG_BIN="/usr/pgsql-${PG_VERSION}/bin"
  [[ -x "${PG_BIN}/initdb" ]] \
    || { echo "initdb не найден. Установите пакет postgresql${PG_VERSION}-server."; exit 1; }
fi

if systemctl list-unit-files | grep -q "^postgresql-${PG_VERSION}.service"; then
  PG_SERVICE="postgresql-${PG_VERSION}"
elif systemctl list-unit-files | grep -q "^postgresql.service"; then
  PG_SERVICE="postgresql"
else
  echo "systemd-служба PostgreSQL не найдена. Убедитесь, что серверный пакет установлен."
  exit 1
fi

echo "[1/5] initdb найден: ${PG_BIN}/initdb"
echo "[1/5] Служба PostgreSQL: ${PG_SERVICE}"

# ──────────────────────────────
# Шаг 3. Инициализация кластера (с контрольными суммами)
# ──────────────────────────────
echo "[2/5] Инициализация кластера (с контрольными суммами)..."
if [[ -d "${PG_DATA}" && -f "${PG_DATA}/PG_VERSION" ]]; then
  echo "Кластер уже существует, initdb пропущен."
else
  mkdir -p "${PG_DATA}"
  chmod 700 "${PG_DATA}"
  chown -R "${PG_USER}:${PG_USER}" "${PG_DATA}"
  sudo -u "${PG_USER}" "${PG_BIN}/initdb" --data-checksums -D "${PG_DATA}"
fi

# ──────────────────────────────
# Шаг 4. Бэкап конфигов
# ──────────────────────────────
CONF="${PG_DATA}/postgresql.conf"
HBA="${PG_DATA}/pg_hba.conf"

echo "[3/5] Бэкап конфигов…"
TIMESTAMP=$(date +%Y%m%d%H%M%S) # чтобы хранить много предыдущих версий
cp "${CONF}" "${CONF}.bak.${TIMESTAMP}"
cp "${HBA}"  "${HBA}.bak.${TIMESTAMP}"

find "${PG_DATA}" -maxdepth 1 -type f -name '*.bak.*' -mtime "+${PG_DELETE_BACKUP}" -delete

# ──────────────────────────────
# Шаг 5. Настройка конфигов
# ──────────────────────────────
echo "[4/5] Настройка конфигов..."

# • postgresql.conf — любые IP, стандартный порт
sed -ri "s/^[#]?listen_addresses\s*=.*/listen_addresses = '*'/" "${CONF}"
sed -ri "s/^[#]?port\s*=.*/port = 5432/" "${CONF}"

# • pg_hba.conf — IPv4 и IPv6, авторизация md5
grep -q "0.0.0.0/0" "${HBA}" || {
  {
    echo ''
    echo 'host all all 0.0.0.0/0 md5'
    echo 'host all all ::/0      md5'
  } >> "${HBA}"
}

# ──────────────────────────────
# Шаг 6. Включение автозапуска и запуск службы
# ──────────────────────────────
echo "[5/5] Запуск и enable службы..."
systemctl enable "${PG_SERVICE}"
systemctl restart "${PG_SERVICE}"

echo "Готово! Проверьте подключение: psql -h <IP> -U postgres -d postgres"

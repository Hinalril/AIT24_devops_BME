#!/usr/bin/env bash
#
# 06_demo.sh – развёртывание Demo-БД PostgresPro
#
# 1. Включаем / запускаем службу postgresql
# 2. Создаём (если нет) базу demo_db и роль demo_user
# 3. Скачиваем выбранный архив (small|medium|big) и распаковываем .sql
# 4. Импортируем дамп в demo_db
#
# Запускать от root:  sudo ./06_demo.sh

set -e

# ──────────────────────────────
# 0. проверка root
# ──────────────────────────────
if (( EUID != 0 )); then
  echo "Запустите скрипт от root (sudo)." >&2
  exit 1
fi

# ──────────────────────────────
# 1. переменные
# ──────────────────────────────
BASE_URL="https://edu.postgrespro.ru"
ARCHIVE_URL="${BASE_URL}/demo-small.zip"        # фиксированная small-версия
TMPDIR="$(mktemp -d)"
ZIP_FILE="${TMPDIR}/demo-small.zip"

DB_NAME="demo_db"
DB_USER="demo_user"
DB_PASS="pass"

# ──────────────────────────────
# 2. запускаем службу postgresql
# ──────────────────────────────
echo "[1/4] Включаем и запускаем службу postgresql"
systemctl enable --now postgresql

# переходим в нейтральную директорию, чтобы psql не ругался на cwd
cd /tmp

# ──────────────────────────────
# 3. создаём базу и роль (идемпотентно)
# ──────────────────────────────
echo "[2/4] Создаём (если нужно) базу и роль"

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};"
fi

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
fi

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

# ──────────────────────────────
# 4. скачиваем и распаковываем
# ──────────────────────────────
echo "[3/4] Скачиваем и распаковываем demo-дамп"
curl -L "${ARCHIVE_URL}" -o "${ZIP_FILE}"
unzip -o "${ZIP_FILE}" -d "${TMPDIR}"

SQL_FILE=$(find "${TMPDIR}" -type f -name '*.sql' | head -n1)
[[ -f "${SQL_FILE}" ]] || { echo "Ошибка: SQL-дамп не найден"; exit 1; }

# делаем доступным для postgres
chown -R postgres:postgres "${TMPDIR}"
chmod -R 750 "${TMPDIR}"

# ──────────────────────────────
# 5. импорт в demo_db
# ──────────────────────────────
echo "[4/4] Импортируем данные в ${DB_NAME}"

#  убираем из дампа строки CREATE DATABASE / \connect demo
sed -e '/^CREATE DATABASE/d' -e '/^\\connect demo/d' "${SQL_FILE}" \
  | sudo -u postgres psql -d "${DB_NAME}"

echo "Готово: «${DB_NAME}» наполнена, роль «${DB_USER}» имеет доступ."

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
# Шаг 0. Требования запустить от root
# ──────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт от root!"
  exit 1
fi

# ──────────────────────────────
# Шаг 1. Переменные
# ──────────────────────────────
BASE_URL="https://edu.postgrespro.ru"
ARCHIVE_URL="${BASE_URL}/demo-small.zip"   # фиксируем small-версию дампа
TMPDIR="$(mktemp -d)"
ZIP="${TMPDIR}/demo-small.zip"

DB_NAME="demo_db"
DB_USER="demo_user"
DB_PASS="pass"

# ──────────────────────────────
# Шаг 2. Запускаем PostgreSQL
# ──────────────────────────────
echo "[1/4] Включаем и запускаем службу postgresql"
systemctl enable --now postgresql

# ──────────────────────────────
# Шаг 3. База и пользователь
# ──────────────────────────────
echo "[2/4] Создаём (если нужно) базу и роль"
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}') THEN
    PERFORM dblink_exec('dbname=postgres', 'CREATE DATABASE ${DB_NAME}');
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
SQL

# ──────────────────────────────
# Шаг 4. Скачиваем архив и распаковываем
# ──────────────────────────────
echo "[3/4] Скачиваем и распаковываем demo-дамп (${SIZE})"
curl -L "${ARCHIVE_URL}" -o "${ZIP}"
SQL_FILE=$(unzip -q -o "${ZIP}" -d "${TMPDIR}" '*.sql' -x '__MACOSX/*' | awk -F': ' '/inflating:/ {print $2; exit}')
[[ -f "$SQL_FILE" ]] || { echo "SQL-файл в архиве не найден"; exit 1; }

# ──────────────────────────────
# Шаг 5.  Импорт дампа
# ──────────────────────────────
echo "[4/4] Импортируем данные в ${DB_NAME}"
sudo -u postgres psql -d "${DB_NAME}" -f "${SQL_FILE}"

echo "Готово: база «${DB_NAME}» создана и наполнена. Пользователь «${DB_USER}» имеет полный доступ."

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
# Шаг 2. Запускаем службу PostgreSQL
# ──────────────────────────────
echo "[1/4] Включаем и запускаем службу postgresql"
systemctl enable --now postgresql

# Перейдём в безопасный каталог, чтобы psql не жаловался на cwd
cd /tmp

# ──────────────────────────────
# Шаг 3. Создаём базу и роль (идемпотентно)
# ──────────────────────────────
echo "[2/4] Создаём (если нужно) базу и роль"

# проверяем наличие базы demo_db
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  echo "→ создаю базу ${DB_NAME}"
  sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};"
else
  echo "→ база ${DB_NAME} уже существует"
fi

# проверяем наличие роли demo_user
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
  echo "→ создаю роль ${DB_USER}"
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
else
  echo "→ роль ${DB_USER} уже существует"
fi

# выдаём все привилегии на базу
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

# ──────────────────────────────
# Шаг 4. Скачиваем архив и распаковываем
# ──────────────────────────────
echo "[3/4] Скачиваем и распаковываем demo-дамп"
curl -L "${ARCHIVE_URL}" -o "${ZIP}"
unzip -o "${ZIP}" -d "${TMPDIR}"               # извлекаем всё, тихий режим не нужен
SQL_FILE=$(find "${TMPDIR}" -type f -name '*.sql' | head -n1)

[[ -f "${SQL_FILE}" ]] || { echo "Ошибка: SQL-файл не найден"; exit 1; }

# Делаем файл читаемым для пользователя postgres
sudo chown -R postgres:postgres "${TMPDIR}"
sudo chmod -R 750 "${TMPDIR}"

# ──────────────────────────────
# Шаг 5.  Импорт дампа
# ──────────────────────────────
echo "[4/4] Импортируем данные в ${DB_NAME}"
sudo -u postgres psql -d "${DB_NAME}" -f "${SQL_FILE}"

echo "Готово: база «${DB_NAME}» создана и наполнена. Пользователь «${DB_USER}» имеет полный доступ."

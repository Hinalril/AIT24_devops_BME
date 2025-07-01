#!/usr/bin/env bash
#
# 06_demo_new_user.sh – добавление новых пользователей в PostgreSQL и настройка прав доступа для него
#
# 1.
# 2.
# 3.
#
# Запускать от root:  sudo ./06_demo_new_user.sh

set -e

# ──────────────────────────────
# 0. проверка root
# ──────────────────────────────
if (( EUID != 0 )); then
  echo "Запустите скрипт от root (sudo)." >&2
  exit 1
fi

# ──────────────────────────────
# 1.  Ввод общих параметров
# ──────────────────────────────
read -rp "Введите имя базы (по умолчанию demo_db): " DB_NAME
DB_NAME=${DB_NAME:-demo_db}

read -rp "Схема, к которой выдаём права (по умолчанию bookings): " SCHEMA_NAME
SCHEMA_NAME=${SCHEMA_NAME:-bookings}

# набор прав по умолчанию: SELECT, INSERT, UPDATE, DELETE
DEFAULT_PRIVS="SELECT,INSERT,UPDATE,DELETE"

read -rp "Список привилегий для таблиц/SEQ (ENTER = ${DEFAULT_PRIVS}): " PRIVS
PRIVS=${PRIVS:-$DEFAULT_PRIVS}

echo
echo "Работаем с базой:      $DB_NAME"
echo "Схема:                 $SCHEMA_NAME"
echo "Привилегии:            $PRIVS"
echo

# ──────────────────────────────
# 2.  Основной интерактивный цикл
# ──────────────────────────────
while true; do
  read -rp "Введите имя нового пользователя (ENTER = выход): " DB_USER
  [[ -z $DB_USER ]] && { echo "Выход."; break; }

  read -srp "Введите пароль для ${DB_USER}: " DB_PASS
  echo

  # 2.1  создаём пользователя (если нет)
  if psql -U postgres -d "$DB_NAME" -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
    echo "→ Пользователь '${DB_USER}' уже существует — пропускаю CREATE."
  else
    echo "→ Создаю роль '${DB_USER}'"
    psql -U postgres -d "$DB_NAME" -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
  fi

  # 2.2  выдаём права (если ещё не выдавались)
  HAS_USAGE=$(psql -U postgres -d "$DB_NAME" -tAc \
     "SELECT 1 FROM information_schema.role_table_grants
       WHERE grantee='${DB_USER}' LIMIT 1")
  if [[ -z $HAS_USAGE ]]; then
    echo "→ Выдаю права на схему и объекты"
    psql -U postgres -d "$DB_NAME" <<-EOSQL
      GRANT USAGE,CREATE ON SCHEMA ${SCHEMA_NAME} TO ${DB_USER};
      GRANT ${PRIVS} ON ALL TABLES     IN SCHEMA ${SCHEMA_NAME} TO ${DB_USER};
      GRANT ${PRIVS} ON ALL SEQUENCES  IN SCHEMA ${SCHEMA_NAME} TO ${DB_USER};
      -- будущие объекты
      ALTER DEFAULT PRIVILEGES IN SCHEMA ${SCHEMA_NAME}
        GRANT ${PRIVS} ON TABLES    TO ${DB_USER};
      ALTER DEFAULT PRIVILEGES IN SCHEMA ${SCHEMA_NAME}
        GRANT ${PRIVS} ON SEQUENCES TO ${DB_USER};
EOSQL
  else
    echo "→ Права для '${DB_USER}' уже выдавались — пропускаю GRANT."
  fi

  echo "Готово для пользователя '${DB_USER}'."
  echo "---------------------------------------------"
done

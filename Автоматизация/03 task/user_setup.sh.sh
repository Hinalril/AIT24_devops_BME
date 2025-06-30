#!/usr/bin/env bash
#
# user_setup.sh — автоматизация задания «LVM для PostgreSQL +-расширение root +-snapshot demo»
# sudo-правило для группы wheel
# создание группы guest
# создаёт пользователей, добавляя их в эту группу.
#
# Запускать от root:  sudo ./add_wheel_users.sh

set -e

# ──────────────────────────────
# Шаг 0. Подготовка
# ──────────────────────────────
# 0.1. включаем правило для wheel в sudoers (с паролем)
if ! grep -Eq '^[[:space:]]*%wheel[[:space:]]+ALL' /etc/sudoers ; then
  sed -i 's/^[#[:space:]]*\(%wheel[[:space:]].*ALL\)/\1/' /etc/sudoers
  echo "[INFO] Разрешение sudo для группы wheel активировано."
fi

# 0.2. создаём группу guest, если её нет
if ! getent group guest >/dev/null ; then
  groupadd guest
  echo "[INFO] Группа guest создана."
fi

wheel_users=()   # для итогового вывода
guest_users=()

# ──────────────────────────────
# Шаг 1. Интерактивный цикл по созданию пользователей
# ──────────────────────────────
while true; do
  read -r -p "Добавить пользователя? [д/y | н/n]: " ans
  ans=$(tr '[:upper:]' '[:lower:]' <<<"$ans")
  [[ $ans =~ ^(н|n)$ ]] && break
  [[ $ans =~ ^(д|y)$ ]] || { echo "Введите 'д' или 'н'"; continue; }

  # 1. выбор роли
  read -r -p "Тип пользователя: wheel(w) / guest(g): " role
  role=$(tr '[:upper:]' '[:lower:]' <<<"$role")
  [[ $role =~ ^(w|g)$ ]] || { echo "Введите 'w' или 'g'"; continue; }

  # 2. имя пользователя
  read -r -p "Имя пользователя: " user
  [[ -z $user ]] && { echo "Имя не может быть пустым."; continue; }

  # 3. создание или проверка существования
  if id "$user" &>/dev/null ; then
    echo "[INFO] $user уже существует."
  else
    useradd -m -s /bin/bash "$user"
    # установка пароля
    while true; do
      read -rs -p "Пароль для $user: " p1; echo
      read -rs -p "Повторите пароль: " p2; echo
      [[ $p1 == "$p2" && -n $p1 ]] && break
      echo "Пароли не совпали, попробуйте ещё раз."
    done
    echo "$user:$p1" | chpasswd
    unset p1 p2
    echo "[INFO] Пользователь $user создан."
  fi

  # 4. включаем в нужную группу
  case $role in
    w)
      usermod -aG wheel "$user"
      wheel_users+=("$user")
      echo "[INFO] $user добавлен в группу wheel."
      ;;
    g)
      usermod -aG guest "$user"
      guest_users+=("$user")
      echo "[INFO] $user добавлен в группу guest."
      ;;
  esac
done

# ──────────────────────────────
# 2. Итоговый отчёт: кто создан
# ──────────────────────────────
[[ ${#wheel_users[@]} -gt 0 ]] && echo "wheel-пользователи: ${wheel_users[*]}"
[[ ${#guest_users[@]} -gt 0 ]]  && echo "guest-пользователи: ${guest_users[*]}"
[[ ${#wheel_users[@]} -eq 0 && ${#guest_users[@]} -eq 0 ]] && \
  echo "Новые аккаунты не созданы."

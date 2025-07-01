#!/bin/bash
#
# dnf_setup.sh - автоматизация задания №4 по устаовке с помщью пакетного менеджера различных утилит
#
# Запускать от root:  sudo ./add_wheel_users.sh


# ──────────────────────────────
# Шаг 0. Требования запустить от root
# ──────────────────────────────
require_root() {
  [[ $(id -u) -eq 0 ]] || { echo "Запустите скрипт от root!"; exit 1; }
}

# ──────────────────────────────
# Шаг 1. Подключаем дополнительные репозитории (если ещё не включены)
# ──────────────────────────────
# EPEL 8 – пакет для screen и pwgen
if ! rpm -q oracle-epel-release-el8 >/dev/null 2>&1; then
    echo "==> Устанавливаем метапакет oracle-epel-release-el8 (EPEL 8)…"
    dnf -y install oracle-epel-release-el8
fi

echo "==> Обновляем кэш репозиториев…"
dnf makecache -y

# ──────────────────────────────
# Шаг 2. Определяем группы пакетов
# ──────────────────────────────
editors=(vim-enhanced nano mc screen)

network=(wget curl telnet nmap-ncat tcpdump net-tools bind-utils)

storage=(autofs nfs-utils cloud-utils-growpart lsof sysfsutils sg3_utils)

monitor=(sysstat)

general=(pwgen bc unzip glibc-langpack-ru)

devtools=(git)

# Единый массив для установки
all_pkgs=(
  "${editors[@]}"
  "${network[@]}"
  "${storage[@]}"
  "${monitor[@]}"
  "${general[@]}"
  "${devtools[@]}"
)

# ──────────────────────────────
# Шаг 3. Устанавливаем базовые утилиты
# ──────────────────────────────
echo "==> Устанавливаем базовые утилиты (${#all_pkgs[@]} пакетов)…"
dnf install -y "${all_pkgs[@]}"

# ──────────────────────────────
# Шаг 4. Устанавливаем PostgreSQL 15
# ──────────────────────────────
echo "==> Переключаемся на модуль PostgreSQL 15 и ставим сервер+клиент…"
dnf module reset  -y postgresql
dnf module enable -y postgresql:15
dnf install       -y postgresql-server postgresql

# ──────────────────────────────
# Шаг 5. Проверка, что всё установлено
# ──────────────────────────────
missing=()
for pkg in "${all_pkgs[@]}" postgresql postgresql-server; do
  if ! rpm -q "$pkg" &>/dev/null; then
    missing+=("$pkg")
  fi
done

if ((${#missing[@]})); then
  echo "Не удалось установить следующие пакеты: ${missing[*]}" >&2
  exit 2
else
  echo "Проверка пройдена успешно: все пакеты на месте."
fi

# ──────────────────────────────
# Шаг 6. Итоговый отчёт
# ──────────────────────────────
echo -e "\n===== Итоговая сводка ====="
echo "Редакторы и управление сессиями:"
printf '  • %s\n' "${editors[@]}"

echo -e "\nСетевые клиенты и диагностика:"
printf '  • %s\n' "${network[@]}"

echo -e "\nФайловые системы и хранение:"
printf '  • %s\n' "${storage[@]}"

echo -e "\nСистемный мониторинг и диагностика:"
printf '  • %s\n' "${monitor[@]}"

echo -e "\nУтилиты общего назначения:"
printf '  • %s\n' "${general[@]}"

echo -e "\nРазработка и контроль версий:"
printf '  • %s\n' "${devtools[@]}"

echo -e "\nУстановлен модуль PostgreSQL 15:"
echo '  • postgresql-server (15)'
echo '  • postgresql (клиент 15)'
echo "==========================="
echo "Готово."

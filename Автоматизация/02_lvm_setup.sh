#!/usr/bin/env bash
#
# lvm_setup.sh — автоматизация задания «LVM для PostgreSQL +-расширение root +-snapshot demo»
#
# Запускать от root:  sudo ./add_wheel_users.sh
#
# ПЕРЕД СТАРТОМ: при необходимости поправьте переменные в секции «НАСТРОЙКИ»

set -e

#──────────────────────────
# НАСТРОЙКИ (редактируйте)
#──────────────────────────
DISK="/dev/sdb"          # дополнительный диск под PostgreSQL
VG="ol_vbox"                  # существующая Volume Group (root расположена здесь)
PGLV_NAME="pglv"         # имя логического тома под /var/lib/pgsql
PGLV_SIZE="8G"           # размер тома под PostgreSQL
PG_MOUNT="/var/lib/pgsql"

ROOT_LV="root"           # имя корневого LV внутри $VG
ROOT_EXPAND="+1G"        # сколько добавить к корню

SNAP_SIZE="1G"           # объём CoW-области снапшота
TMP_FILE_MB=500          # сколько «мусора» писать для демонстрации (в МБ)
#──────────────────────────

GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

msg()   { printf "%b[INFO]%b %s\n"  "$YELLOW"  "$RESET" "$*"; }
done_() { printf "%b[DONE]%b %s\n"  "$GREEN"   "$RESET" "$*"; }


# ──────────────────────────────
# Шаг 0. Требования запустить от root
# ──────────────────────────────
require_root() {
  [[ $(id -u) -eq 0 ]] || { echo "Запустите скрипт от root!"; exit 1; }
}

run() {
  msg "$*"
  eval "$@"
  done_ "$*"
}

#──────────────────────────
# ШАГ 1. PostgreSQL на отдельном LV
#──────────────────────────
setup_pg_lv() {
  msg "=== ШАГ 1. Настройка тома под PostgreSQL ==="

  if ! pvs | grep -q "^${DISK}"; then
      run "pvcreate ${DISK}"
  else
      msg "Диск ${DISK} уже инициализирован как PV — пропускаю pvcreate"
  fi

  if ! vgdisplay "${VG}" | grep -q "${DISK}"; then
      run "vgextend ${VG} ${DISK}"
  else
      msg "Диск уже входит в VG ${VG} — пропускаю vgextend"
  fi

  if ! lvs "${VG}/${PGLV_NAME}" &>/dev/null; then
      run "lvcreate -L ${PGLV_SIZE} -n ${PGLV_NAME} ${VG}"
  else
      msg "LV ${PGLV_NAME} уже существует — пропускаю lvcreate"
  fi

  if ! blkid "/dev/${VG}/${PGLV_NAME}" &>/dev/null; then
      run "mkfs.xfs -f /dev/${VG}/${PGLV_NAME}"
  else
      msg "ФС на /dev/${VG}/${PGLV_NAME} уже есть — пропускаю mkfs"
  fi

  run "mkdir -p ${PG_MOUNT}"

  fstab_entry="/dev/${VG}/${PGLV_NAME} ${PG_MOUNT} xfs defaults 0 2"
  if ! grep -Fxq "${fstab_entry}" /etc/fstab; then
      run "echo '${fstab_entry}' >> /etc/fstab"
  else
      msg "Запись для ${PGLV_NAME} уже есть в /etc/fstab — пропускаю"
  fi

  run "mount -a"
  done_ "Том под PostgreSQL примонтирован в ${PG_MOUNT}"
}

#──────────────────────────
# ШАГ 2. Расширение корневого раздела
#──────────────────────────
expand_root() {
  msg "=== ШАГ 2. Увеличение корневого LV на ${ROOT_EXPAND} ==="
  run "lvextend -r -L ${ROOT_EXPAND} /dev/${VG}/${ROOT_LV}"
  done_ "Корневой LV расширен"
}

#──────────────────────────
# ШАГ 3. Снапшот → изменения → откат
#──────────────────────────
snapshot_demo() {
  msg "=== ШАГ 3. Демонстрация snapshot ==="

  if lvs "${VG}/rootsnap" &>/dev/null; then
      msg "Снапшот rootsnap уже существует — удаляю"
      run "lvremove -f /dev/${VG}/rootsnap"
  fi

  run "lvcreate -L ${SNAP_SIZE} -s -n rootsnap /dev/${VG}/${ROOT_LV}"
  run "mkdir -p /mnt/rootsnap"
  run "mount -o ro /dev/${VG}/rootsnap /mnt/rootsnap"
  done_ "Снапшот примонтирован в /mnt/rootsnap (только чтение)"

  msg "Создаю ${TMP_FILE_MB} МБ данных во /var/tmp для имитации изменений"
  run "dd if=/dev/zero of=/var/tmp/bigfile bs=1M count=${TMP_FILE_MB} status=progress"
  run "sync"

  msg "Заполняемость CoW-области:"
  lvs -o lv_name,lv_size,data_percent,origin /dev/${VG}/rootsnap

  run "umount /mnt/rootsnap"

  msg "Сейчас выполню откат к снапшоту (lvconvert --merge)"
  run "lvconvert --merge /dev/${VG}/rootsnap"
  echo
  echo "${YELLOW}Внимание! Для завершения merge требуется перезагрузка.${RESET}"
  read -r -p "Перезагрузить систему сейчас? [y/N] " ans
  if [[ ${ans,,} == y ]]; then
      run "reboot"
  else
      msg "Перезагрузку можно выполнить позже командой reboot"
  fi
}

#──────────────────────────
# ГЛАВНЫЙ БЛОК
#──────────────────────────
require_root
setup_pg_lv
expand_root
snapshot_demo

done_ "Сценарий завершён успешно"

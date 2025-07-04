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
VG="ol"                  # существующая Volume Group (root расположена здесь)
PGLV_NAME="pglv"         # имя логического тома под /var/lib/pgsql
PGLV_SIZE="8G"           # размер тома под PostgreSQL
PG_MOUNT="/var/lib/pgsql"

ROOT_LV="root"           # имя корневого LV внутри $VG
ROOT_EXPAND="+1G"        # сколько добавить к корню

SNAP_SIZE="0.8G"           # объём CoW-области снапшота
TMP_FILE_MB=500          # сколько «мусора» писать для демонстрации (в МБ)
#──────────────────────────

# ──────────────────────────────
# Шаг 0. Требования запустить от root
# ──────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт от root!"
  exit 1
fi

#──────────────────────────
# ШАГ 1. PostgreSQL на отдельном LV
#──────────────────────────
setup_pg_lv() {
  echo "=== ШАГ 1. Настройка тома под PostgreSQL ==="

  if ! pvs | grep -q "^${DISK}"; then
    pvcreate "${DISK}"
  else
    echo "Пропускаю pvcreate: диск ${DISK} уже инициализирован как PV."
  fi

  if ! vgdisplay "${VG}" | grep -q "${DISK}"; then
    vgextend "${VG}" "${DISK}"
  else
    echo "Пропускаю vgextend: диск уже входит в VG ${VG}."
  fi

  if ! lvs "${VG}/${PGLV_NAME}" &>/dev/null; then
    lvcreate -L "${PGLV_SIZE}" -n "${PGLV_NAME}" "${VG}"
  else
    echo "Пропускаю lvcreate: LV ${PGLV_NAME} уже существует."
  fi

  if ! blkid "/dev/${VG}/${PGLV_NAME}" &>/dev/null; then
    mkfs.xfs -f "/dev/${VG}/${PGLV_NAME}"
  else
    echo "Пропускаю mkfs: файловая система уже есть на /dev/${VG}/${PGLV_NAME}."
  fi

  mkdir -p "${PG_MOUNT}"

  fstab_entry="/dev/${VG}/${PGLV_NAME} ${PG_MOUNT} xfs defaults 0 2"
  if ! grep -Fxq "${fstab_entry}" /etc/fstab; then
    echo "${fstab_entry}" >> /etc/fstab
  else
    echo "Пропускаю запись в fstab: запись уже существует."
  fi

  mount -a
  echo "Том под PostgreSQL примонтирован в ${PG_MOUNT}"
}

#──────────────────────────
# ШАГ 2. Расширение корневого раздела
#──────────────────────────
expand_root() {
  echo "=== ШАГ 2. Увеличение корневого LV на ${ROOT_EXPAND} ==="
  lvextend -r -L "${ROOT_EXPAND}" "/dev/${VG}/${ROOT_LV}"
  echo "Корневой LV расширен"
}

#──────────────────────────
# ШАГ 3. Снапшот -> изменения -> откат
#──────────────────────────
snapshot_demo() {
  echo "=== ШАГ 3. Демонстрация snapshot ==="

  if lvs "${VG}/rootsnap" &>/dev/null; then
    echo "Удаляю старый снапшот rootsnap"
    lvremove -f "/dev/${VG}/rootsnap"
  fi

  lvcreate -L "${SNAP_SIZE}" -s -n rootsnap "/dev/${VG}/${ROOT_LV}"
  mkdir -p /mnt/rootsnap
  mount -o ro,nouuid "/dev/${VG}/rootsnap" /mnt/rootsnap
  echo "Снапшот примонтирован в /mnt/rootsnap (только чтение)"

  echo "Создаю ${TMP_FILE_MB} МБ данных в /var/tmp для имитации изменений"
  dd if=/dev/zero of=/var/tmp/bigfile bs=1M count="${TMP_FILE_MB}" status=progress
  sync

  echo "Заполняемость CoW-области:"
  lvs -o lv_name,lv_size,data_percent,origin "/dev/${VG}/rootsnap"

  umount /mnt/rootsnap

  echo "Выполняю откат к снапшоту (lvconvert --merge)"
  lvconvert --merge "/dev/${VG}/rootsnap"
  echo
  echo "Внимание! Для завершения merge требуется перезагрузка."
  read -r -p "Перезагрузить систему сейчас? [y/N] " ans
  if [[ "${ans,,}" == "y" ]]; then
    reboot
  else
    echo "Перезагрузку можно выполнить позже командой reboot"
  fi
}

#──────────────────────────
# ГЛАВНЫЙ БЛОК
#──────────────────────────
setup_pg_lv
expand_root
snapshot_demo

echo "Сценарий завершён успешно"

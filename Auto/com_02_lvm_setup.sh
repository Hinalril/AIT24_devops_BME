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
# Проверяем, запущен ли скрипт с привилегиями суперпользователя (sudo)
    # $EUID    — переменная Bash, содеражит UID текущего процесса
    # $EUID    — вернет 0, если script запущен от sudo
    # -ne 0    — оператор “not equal”. Проверяет, что значение слева не равно 0
    # [[ … ]]  — внутри выражение проверяется на истинность. Код = 0, если истина. Код = 1, если ложь.
    # [[ $EUID -ne 0 ]] — истина, если текущий UID не 0 (то есть не запущено под sudo)
    # если не равно 0, то выведется сообщение и script завершится с кодом 1
if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт от root!"
  exit 1
fi

#──────────────────────────
# ШАГ 1. PostgreSQL на отдельном LV
#──────────────────────────
setup_pg_lv() {
  echo "=== ШАГ 1. Настройка тома под PostgreSQL ==="

  # 1. Инициализация физического тома (PV) на диске, если не сделано
  #    pvs       — показывает список PV
  #    grep -q   — тихий режим, проверяем, есть ли строка, начинающаяся с имени диска
  if ! pvs | grep -q "^${DISK}"; then
    # pvcreate  — инициализирует указанный диск как LVM PV
    pvcreate "${DISK}"
  else
    echo "Пропускаю pvcreate: диск ${DISK} уже инициализирован как PV."
  fi

  # 2. Добавление PV в Volume Group (VG), если диск ещё не добавлен
  #    vgdisplay — показывает параметры VG
  #    grep -q   — проверяем, упоминается ли диск в выводе vgdisplay
  if ! vgdisplay "${VG}" | grep -q "${DISK}"; then
    # vgextend  — расширяет существующую VG, добавляя новый PV
    vgextend "${VG}" "${DISK}"
  else
    echo "Пропускаю vgextend: диск уже входит в VG ${VG}."
  fi

  # 3. Создание логического тома (LV) для PostgreSQL, если он ещё не существует
  #    lvs       — показывает список LV
  if ! lvs "${VG}/${PGLV_NAME}" &>/dev/null; then
    # lvcreate  — создаёт LV размером PGLV_SIZE с именем PGLV_NAME в VG
    lvcreate -L "${PGLV_SIZE}" -n "${PGLV_NAME}" "${VG}"
  else
    echo "Пропускаю lvcreate: LV ${PGLV_NAME} уже существует."
  fi

  # 4. Форматирование LV в файловую систему XFS, если не отформатировано
  #    blkid     — проверяет наличие ФС на устройстве
  if ! blkid "/dev/${VG}/${PGLV_NAME}" &>/dev/null; then
    # mkfs.xfs  — создаёт XFS ФС, -f принудительно перезаписывает старую
    mkfs.xfs -f "/dev/${VG}/${PGLV_NAME}"
  else
    echo "Пропускаю mkfs: файловая система уже есть на /dev/${VG}/${PGLV_NAME}."
  fi

  # 5. Создание точки монтирования
  mkdir -p "${PG_MOUNT}"

  # 6. Добавление записи в /etc/fstab для автозагрузки file system (FS)
  fstab_entry="/dev/${VG}/${PGLV_NAME} ${PG_MOUNT} xfs defaults 0 2"
  #   grep -Fxq — точное сравнение строк, тихий режим
  if ! grep -Fxq "${fstab_entry}" /etc/fstab; then
    echo "${fstab_entry}" >> /etc/fstab
  else
    echo "Пропускаю запись в fstab: запись уже существует."
  fi

  # 7. Монтируем все FS из fstab
  mount -a
  echo "Том под PostgreSQL примонтирован в ${PG_MOUNT}"
}

#──────────────────────────
# ШАГ 2. Расширение корневого раздела
#──────────────────────────
expand_root() {
  echo "=== ШАГ 2. Увеличение корневого LV на ${ROOT_EXPAND} ==="

  # Команда lvextend:
  #   -r                      — одновременно расширить ФС (resize) после изменения размера LV
  #   -L "${ROOT_EXPAND}"     — добавить к текущему размеру указанное значение (например, +1G)
  #   "/dev/${VG}/${ROOT_LV}" — путь к логическому тому (VG имя группы, ROOT_LV имя тома)
  lvextend -r -L "${ROOT_EXPAND}" "/dev/${VG}/${ROOT_LV}"
  echo "Корневой LV расширен"
}

#──────────────────────────
# ШАГ 3. Снапшот -> изменения -> откат
#──────────────────────────
snapshot_demo() {
  echo "=== ШАГ 3. Демонстрация snapshot ==="

  # 3.1. Удаляем старый снапшот, если он остался от предыдущего запуска
  #    lvs "${VG}/rootsnap" — проверяет существование LV rootsnap
  #    &>/dev/null          — скрывает вывод, важен только код возврата
  #    lvremove -f          — принудительно удаляет логический том
  if lvs "${VG}/rootsnap" &>/dev/null; then
    echo "Удаляю старый снапшот rootsnap"
    lvremove -f "/dev/${VG}/rootsnap"
  fi

  # 3.2. Создаём новый снапшот корневого тома
  #    -L "${SNAP_SIZE}" — размер CoW-области снапшота
  #    -s               — флаг snapshot
  #    -n rootsnap      — имя создаваемого снапшота
  lvcreate -L "${SNAP_SIZE}" -s -n rootsnap "/dev/${VG}/${ROOT_LV}"

  # 3.3. Монтируем снапшот в режиме только для чтения
  mkdir -p /mnt/rootsnap
  #    -o ro         — монтировать в режиме only-read
  #    -o nouuid     — не монтировать UUID, чтобы избежать конфликтов
  mount -o ro,nouuid "/dev/${VG}/rootsnap" /mnt/rootsnap
  echo "Снапшот примонтирован в /mnt/rootsnap (только чтение)"

  # 3.4. Генерируем большие данные для демонстрации изменений
  echo "Создаю ${TMP_FILE_MB} МБ данных в /var/tmp для имитации изменений"
  #    dd if=/dev/zero — читаем нули
  #       of=/var/tmp/bigfile — записываем в файл
  #       bs=1M count=… — размер блока 1 МБ, количество блоков TMP_FILE_MB
  #       status=progress — показывать прогресс
  dd if=/dev/zero of=/var/tmp/bigfile bs=1M count="${TMP_FILE_MB}" status=progress
  sync # дожидаемся записи данных на диск

  # 3.5. Показать заполненность CoW-области снапшота
  echo "Заполняемость CoW-области:"
  #    lvs -o … — выводим колонки: имя LV, размер, процент данных в CoW, исходник (origin)
  lvs -o lv_name,lv_size,data_percent,origin "/dev/${VG}/rootsnap"

  # 3.6. Отмонтировать снапшот перед откатом
  umount /mnt/rootsnap

  # 3.7. Откат к состоянию снапшота
  echo "Выполняю откат к снапшоту (lvconvert --merge)"
  #    lvconvert --merge — объединяет снапшот с исходным томом, возвращая прежнее состояние
  lvconvert --merge "/dev/${VG}/rootsnap"
  echo
  echo "Внимание! Для завершения merge требуется перезагрузка."

  # 3.8. Предложить перезагрузку для применения merge
  read -r -p "Перезагрузить систему сейчас? [y/N] " ans
  # ${ans,,} — приводим ввод к нижнему регистру
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

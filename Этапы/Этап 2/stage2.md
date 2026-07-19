# Этап 2. Отказоустойчивость и резервное копирование

## 8. Создание дополнительных виртуальных машин

### Цель

Для дальнейшей настройки отказоустойчивого кластера PostgreSQL и системы резервного копирования необходимо создать три дополнительные виртуальные машины с Oracle Linux 8.

Вместе с сервером `ol8-pg01`, созданным на первом этапе, лабораторный стенд должен состоять из четырёх VM:

* одного первоначального сервера PostgreSQL;
* двух серверов-реплик;
* отдельного сервера резервного копирования.

### Архитектура стенда

| VM             |        IP-адрес | Назначение                        |  RAM | vCPU | Системный диск | Дополнительный диск |
| -------------- | --------------: | --------------------------------- | ---: | ---: | -------------: | ------------------: |
| `ol8-pg01`     | `192.168.77.11` | первоначальный primary PostgreSQL | 3 GB |    2 |          30 GB |               30 GB |
| `ol8-pg02`     | `192.168.77.12` | синхронная реплика                | 2 GB |    2 |          30 GB |               30 GB |
| `ol8-pg03`     | `192.168.77.13` | асинхронная реплика               | 2 GB |    2 |          30 GB |               30 GB |
| `ol8-backup01` | `192.168.77.20` | сервер резервного копирования     | 2 GB |    2 |          30 GB |               30 GB |

Для новых VM используется динамическая память Hyper-V:

* Startup RAM: `2048 MB`;
* Minimum RAM: `1024 MB`;
* Maximum RAM: `2048 MB`.

### Платформа виртуализации

Виртуальные машины созданы в Microsoft Hyper-V со следующими общими параметрами:

* поколение VM: `Generation 2`;
* виртуальных процессоров: `2`;
* формат дисков: `VHDX`;
* тип дисков: `Dynamically expanding`;
* виртуальный коммутатор: `DevOpsLab`;
* Secure Boot: включён;
* Secure Boot Template: `Microsoft UEFI Certificate Authority`;
* Automatic Checkpoints: отключены;
* операционная система: Oracle Linux 8.10;
* вариант установки: `Minimal Install`.

Файлы виртуальных машин размещаются в каталоге:

```text
H:\DevOpsLab\VMs
```

Установочный ISO расположен по адресу:

```text
H:\DevOpsLab\ISO\OracleLinux-R8-U10-x86_64-dvd.iso
```

### Настройка сети

Все серверы подключены к внутреннему коммутатору Hyper-V `DevOpsLab` и используют ранее созданную NAT-сеть:

```text
192.168.77.0/24
```

Общие сетевые параметры:

| Параметр        | Значение        |
| --------------- | --------------- |
| Шлюз            | `192.168.77.1`  |
| Маска           | `255.255.255.0` |
| DNS 1           | `1.1.1.1`       |
| DNS 2           | `8.8.8.8`       |
| Метод IPv4      | `Manual`        |
| Имя подключения | `eth0`          |

Каждой VM назначен статический адрес. Имена серверов настроены командами `hostnamectl` и сохраняются после перезагрузки:

```text
ol8-pg01.devops.test
ol8-pg02.devops.test
ol8-pg03.devops.test
ol8-backup01.devops.test
```

Пример ручной настройки hostname:

```bash
sudo hostnamectl set-hostname ol8-pg02.devops.test
```

Локальное разрешение имени добавлено в `/etc/hosts`:

```text
192.168.77.12 ol8-pg02.devops.test ol8-pg02
```

### Размещение операционной системы

Oracle Linux устанавливался только на системный диск размером 30 GB.

Для `ol8-pg02`, `ol8-pg03`, `ol8-backup01` дополнительный диск размером 25 GB оставлялся неразмеченным во время установки ОС.

После установки проверялось распределение дисков:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
```

На итоговой конфигурации системные диски содержат:

* EFI-раздел;
* `/boot`;
* системный LVM;
* корневой логический том;
* swap.

Дополнительные диски используются только для данных PostgreSQL или резервных копий.

### Постоянная идентификация дисков

Имена Linux-устройств `/dev/sda` и `/dev/sdb` могут меняться после перезагрузки или изменения порядка подключения VHDX. Поэтому в Ansible используются постоянные идентификаторы WWN из каталога:

```text
/dev/disk/by-id
```

Получение идентификаторов выполнялось командой:

```bash
lsblk -d -o NAME,SIZE,WWN
```

Для дополнительных дисков получены следующие значения:

| VM             | Назначение диска  | Постоянный путь                                          |
| -------------- | ----------------- | -------------------------------------------------------- |
| `ol8-pg01`     | данные PostgreSQL | `/dev/disk/by-id/wwn-0x600224803c5f39a1639cbe8129c5e1de` |
| `ol8-pg02`     | данные PostgreSQL | `/dev/disk/by-id/wwn-0x6002248046aa207f51b1792978745581` |
| `ol8-pg03`     | данные PostgreSQL | `/dev/disk/by-id/wwn-0x6002248072c9d47e7404e7e122cca73e` |
| `ol8-backup01` | резервные копии   | `/dev/disk/by-id/wwn-0x6002248086d2959c5a32fec309fd2a0f` |

Индивидуальные WWN хранятся в `inventory.yaml`. Универсальные playbook не содержат жёстко заданных `/dev/sda` или `/dev/sdb`.

### Настройка управления через Ansible

Управляющим узлом является Ubuntu в WSL 2.

На управляющем узле используются:

* Ansible Core `2.20.1`;
* Python `3.14.4`;
* SSH-ключ `academy_ansible_ed25519`.

На всех управляемых VM установлен Python:

```text
Python 3.12.13
```

Публичный SSH-ключ управляющего узла добавлен пользователю `ansible`:

```bash
ssh-copy-id \
    -i ~/.ssh/academy_ansible_ed25519.pub \
    ansible@192.168.77.12
```

Аналогичная операция выполнена для `192.168.77.13` и `192.168.77.20`.

Доступ без пароля проверялся командой:

```bash
ssh \
    -i ~/.ssh/academy_ansible_ed25519 \
    ansible@192.168.77.12 \
    "hostnamectl --static"
```

### Группы Ansible Inventory

В `inventory.yaml` определены следующие группы:

| Группа                | Назначение                                                           |
| --------------------- | -------------------------------------------------------------------- |
| `postgresql`          | первоначальный сервер `ol8-pg01`                                     |
| `postgresql_cluster`  | все три узла PostgreSQL                                              |
| `postgresql_replicas` | `ol8-pg02` и `ol8-pg03`                                              |
| `backup_servers`      | сервер `ol8-backup01`                                                |
| `stage2_storage`      | узлы, для которых на этапе №2 настраивается дополнительное хранилище |

Проверка структуры inventory:

```bash
ansible-inventory -i inventory.yaml --graph
```

Проверка доступности всех VM:

```bash
ansible all \
    -i inventory.yaml \
    -m ansible.builtin.ping
```

Все четыре узла успешно возвращают:

```text
ping: pong
```

### Подготовка хранилищ

Для настройки дополнительных дисков создан универсальный playbook:

```text
stage2_storage_pb.yaml
```

Параметры конкретного узла — WWN, имя VG, имя LV, размер и точка монтирования — хранятся в `inventory.yaml`.

Playbook выполняет следующие действия:

1. Проверяет наличие обязательных переменных.
2. Проверяет существование диска по WWN.
3. Проверяет, что выбранный диск не содержит системные разделы.
4. Создаёт таблицу разделов GPT.
5. Создаёт LVM-раздел.
6. Создаёт Volume Group.
7. Создаёт Logical Volume.
8. Создаёт файловую систему XFS.
9. Добавляет постоянное монтирование.
10. Выводит итоговую конфигурацию.

Запуск:

```bash
ansible-playbook \
    -i inventory.yaml \
    stage2_storage_pb.yaml \
    --ask-become-pass
```

### Хранилища реплик PostgreSQL

На `ol8-pg02` и `ol8-pg03` созданы:

| Параметр           | Значение         |
| ------------------ | ---------------- |
| VG                 | `vg_postgres`    |
| LV                 | `lv_pgdata`      |
| Размер LV          | 20 GB            |
| Файловая система   | XFS              |
| Точка монтирования | `/var/lib/pgsql` |
| Свободно в VG      | около 10 GB       |

Проверка:

```bash
findmnt /var/lib/pgsql
```

Ожидаемый источник:

```text
/dev/mapper/vg_postgres-lv_pgdata
```

Свободные 10 GB могут использоваться для LVM snapshot или дальнейшего расширения.

### Хранилище сервера резервного копирования

На `ol8-backup01` созданы:

| Параметр           | Значение                  |
| ------------------ | ------------------------- |
| VG                 | `vg_backup`               |
| LV                 | `lv_backup`               |
| Размер LV          | 30 GB                     |
| Файловая система   | XFS                       |
| Точка монтирования | `/var/backups/postgresql` |
| Свободно в VG      | около 10 GB                |

Проверка:

```bash
findmnt /var/backups/postgresql
```

Ожидаемый источник:

```text
/dev/mapper/vg_backup-lv_backup
```

Этот каталог будет использоваться для:

* логических дампов;
* физических резервных копий;
* каталога `pg_probackup`;
* данных Barman;
* данных WAL-G;
* журналов выполнения резервного копирования.

### Проверка идемпотентности

После первоначальной настройки `stage2_storage_pb.yaml` был запущен повторно.

Получен результат:

```text
ol8_backup01 : changed=0 failed=0
ol8_pg02     : changed=0 failed=0
ol8_pg03     : changed=0 failed=0
```

Это подтверждает, что повторный запуск:

* не пересоздаёт разделы;
* не форматирует существующие файловые системы;
* не изменяет LVM без необходимости;
* не создаёт повторные записи в `/etc/fstab`.

## 9. Настройка резервного копирования PostgreSQL

### Цель и текущий статус

Цель пункта №9 — реализовать несколько независимых способов резервного копирования PostgreSQL и разместить резервные копии на отдельной VM `ol8-backup01`.

В соответствии с заданием необходимо настроить:

1. логический дамп по расписанию;
2. физическую резервную копию;
3. `pg_probackup`;
4. Barman;
5. WAL-G.

### Исходная конфигурация

Резервное копирование выполняется с primary-сервера PostgreSQL на отдельную VM:

| Параметр | Значение |
| --- | --- |
| Primary PostgreSQL | `ol8-pg01` |
| IP-адрес primary | `192.168.77.11` |
| Backup-сервер | `ol8-backup01` |
| IP-адрес backup-сервера | `192.168.77.20` |
| Версия PostgreSQL | `15.18` |
| Рабочая база данных | `demo` |
| Размер базы `demo` | около 280 MB |
| Точка монтирования backup-хранилища | `/var/backups/postgresql` |
| Файловая система | XFS |
| Размер LV | 30 GB |
| Свободно в VG | около 10 GB |
| Временная зона | `Asia/Krasnoyarsk`, UTC+7 |

Проверка backup-хранилища:

```bash
hostnamectl --static
findmnt /var/backups/postgresql
df -hT /var/backups/postgresql
vgs vg_backup
lvs /dev/vg_backup/lv_backup
```

Фактический результат:

```text
hostname: ol8-backup01.devops.test
source:   /dev/mapper/vg_backup-lv_backup
target:   /var/backups/postgresql
fstype:   xfs
LV size:  30.00 GB
VG free:  около 10.00 GB
```

Проверка базы на primary:

```bash
sudo -u postgres psql -d demo -tAc \
  "SELECT current_database(),
          pg_is_in_recovery(),
          pg_size_pretty(pg_database_size(current_database()));"
```

Получен результат:

```text
demo|f|280 MB
```

Значение `f` у `pg_is_in_recovery()` подтверждает, что `ol8-pg01` работает как primary.

### Корректировка временной зоны backup-сервера

При создании первого тестового дампа было обнаружено, что `ol8-backup01` использовал временную зону `America/New_York`, поэтому время создания архива отображалось как EDT. При такой конфигурации cron запускал бы задания не по красноярскому времени.

Проверка:

```bash
timedatectl show --property=Timezone --value
```

Настройка правильной временной зоны:

```bash
sudo timedatectl set-timezone Asia/Krasnoyarsk
```

Итоговая проверка:

```bash
date '+%Y-%m-%d %H:%M:%S %Z %z'
```

Получен результат с часовым поясом UTC+7:

```text
2026-07-19 02:43:14 +07 +0700
```

## 9.1. Логический backup с помощью pg_dump

### Ручная реализация

Ниже приведена эквивалентная ручная последовательность настройки. Фактически эти действия автоматизированы Ansible-playbook, описанным далее.

#### Создание отдельной роли PostgreSQL

Для резервного копирования используется отдельная роль `backup_logical`. Пароль роли не должен храниться в открытом виде в скриптах или репозитории.

Создание роли:

```bash
sudo -u postgres psql -d postgres -v ON_ERROR_STOP=1 -c \
  "CREATE ROLE backup_logical LOGIN PASSWORD '<BACKUP_PASSWORD>';"
```

Предоставление прав только на чтение данных:

```bash
sudo -u postgres psql -d demo -v ON_ERROR_STOP=1 -c \
  "GRANT pg_read_all_data TO backup_logical;"
```

Роль не получает права суперпользователя, создания баз данных или изменения данных.

#### Ограничение подключений в pg_hba.conf

Для роли разрешено подключение к базе `demo` только с адреса backup-сервера `192.168.77.20`:

```text
host    demo    backup_logical    192.168.77.20/32    scram-sha-256
host    all     backup_logical    0.0.0.0/0           reject
host    all     backup_logical    ::/0                reject
```

После изменения конфигурации PostgreSQL перечитывает `pg_hba.conf` без перезапуска:

```bash
sudo systemctl reload postgresql
```

Проверка отсутствия ошибок:

```bash
sudo -u postgres psql -d postgres -tAc \
  "SELECT count(*) FROM pg_hba_file_rules WHERE error IS NOT NULL;"
```

Ожидаемый и фактически полученный результат:

```text
0
```

#### Установка клиентских утилит на backup-сервере

На `ol8-backup01` включается модуль PostgreSQL 15 и устанавливаются клиент PostgreSQL и cron:

```bash
sudo dnf module enable -y postgresql:15
sudo dnf install -y postgresql cronie
```

Проверка версии:

```bash
pg_dump --version
```

Фактический результат:

```text
pg_dump (PostgreSQL) 15.18
```

#### Создание системного пользователя и каталогов

Резервное копирование выполняется от отдельного системного пользователя `pgbackup`:

```bash
sudo useradd --system --home-dir /var/lib/pgbackup \
  --create-home --shell /sbin/nologin pgbackup
```

Создание каталогов:

```bash
sudo mkdir -p \
  /var/backups/postgresql/logical \
  /var/backups/postgresql/logs
```

Настройка владельца и прав:

```bash
sudo chown -R pgbackup:pgbackup \
  /var/backups/postgresql/logical \
  /var/backups/postgresql/logs
```

```bash
sudo chmod 0750 \
  /var/backups/postgresql/logical \
  /var/backups/postgresql/logs
```

#### Настройка файла .pgpass

Пароль хранится в файле `/var/lib/pgbackup/.pgpass`:

```text
192.168.77.11:5432:demo:backup_logical:<BACKUP_PASSWORD>
```

Файл должен принадлежать пользователю `pgbackup` и иметь права `0600`:

```bash
sudo chown pgbackup:pgbackup /var/lib/pgbackup/.pgpass
sudo chmod 0600 /var/lib/pgbackup/.pgpass
```

#### Создание логического дампа

Логический backup выполняется в custom-формате PostgreSQL:

```bash
sudo -u pgbackup env \
  PGPASSFILE=/var/lib/pgbackup/.pgpass \
  pg_dump \
    --host=192.168.77.11 \
    --port=5432 \
    --username=backup_logical \
    --dbname=demo \
    --format=custom \
    --file=/var/backups/postgresql/logical/demo.dump
```

Custom-формат позволяет просматривать состав архива через `pg_restore`, выборочно восстанавливать объекты и использовать параллельное восстановление.

#### Проверка логического дампа

Проверка структуры архива:

```bash
pg_restore --list /var/backups/postgresql/logical/demo.dump
```

Создание контрольной суммы:

```bash
sha256sum /var/backups/postgresql/logical/demo.dump \
  > /var/backups/postgresql/logical/demo.dump.sha256
```

Проверка контрольной суммы:

```bash
sha256sum -c /var/backups/postgresql/logical/demo.dump.sha256
```

#### Скрипт и расписание

В итоговой реализации используется скрипт:

```text
/usr/local/sbin/backup_demo_logical.sh
```

Скрипт:

1. формирует имя файла с датой и временем;
2. сначала создаёт временный файл;
3. выполняет `pg_dump` базы `demo`;
4. проверяет архив через `pg_restore --list`;
5. только после проверки переименовывает временный файл в итоговый;
6. создаёт SHA256;
7. удаляет резервные копии старше семи дней;
8. завершается с ненулевым кодом при любой ошибке.

Ручной запуск итогового скрипта:

```bash
sudo -u pgbackup /usr/local/sbin/backup_demo_logical.sh
```

Для защиты от одновременного запуска нескольких копий применяется `flock`.

Запись cron:

```cron
0 1 * * * /usr/bin/flock -n /var/lib/pgbackup/logical_backup.lock /usr/local/sbin/backup_demo_logical.sh >> /var/backups/postgresql/logs/logical_backup.log 2>&1
```

Логический backup создаётся ежедневно в `01:00` по времени `Asia/Krasnoyarsk`.

#### Фактический результат

Первый проверочный архив:

```text
/var/backups/postgresql/logical/demo_20260718_153653.dump
```

Результаты проверки:

```text
Размер:                         22 MB
Формат:                         CUSTOM
Количество записей TOC:         163
Версия исходной базы:           PostgreSQL 15.18
Версия pg_dump:                 PostgreSQL 15.18
Проверка SHA256:                OK
```

### Реализация логического backup через Ansible

Описанная выше конфигурация фактически реализована playbook:

```text
logical_backup_pb.yaml
```

Пароль роли `backup_logical` хранится в зашифрованном файле:

```text
vars/vault.yaml
```

Переменная Ansible Vault:

```yaml
vault_backup_logical_password: "<ENCRYPTED_VALUE>"
```

Playbook автоматически выполняет:

1. проверку обязательных переменных;
2. создание роли `backup_logical`, если она отсутствует;
3. выдачу роли `pg_read_all_data`;
4. добавление управляемого блока в `pg_hba.conf`;
5. reload PostgreSQL;
6. проверку `pg_hba_file_rules`;
7. настройку временной зоны `Asia/Krasnoyarsk`;
8. установку PostgreSQL client и cron;
9. создание пользователя `pgbackup`;
10. создание каталогов и `.pgpass`;
11. установку backup-скрипта;
12. создание задания cron;
13. вывод версии `pg_dump` и итоговых параметров.

Проверка синтаксиса:

```bash
ansible-playbook \
  -i inventory.yaml \
  logical_backup_pb.yaml \
  --syntax-check \
  --ask-vault-pass
```

Запуск:

```bash
ansible-playbook \
  -i inventory.yaml \
  logical_backup_pb.yaml \
  --ask-vault-pass \
  --ask-become-pass
```

После первоначальной настройки playbook был запущен повторно. Получен результат:

```text
ol8_backup01 : changed=0 failed=0
ol8_pg01     : changed=0 failed=0
```

Это подтверждает идемпотентность автоматизации логического backup.

Из-за использования Python 3.12 на управляемых VM системный Python-модуль `dnf` недоступен этому интерпретатору. Поэтому установка пакетов в данном playbook выполняется командой `dnf` через `ansible.builtin.command`, как и в других playbook проекта.

## 9.2. Физический backup с помощью pg_basebackup

### Ручная реализация

Ниже приведена эквивалентная ручная последовательность. Фактическая настройка выполнена Ansible-playbook, описанным далее.

#### Проверка параметров primary

Физическое резервное копирование требует `wal_level=replica` и свободных WAL sender. Проверка:

```bash
sudo -u postgres psql -tAc \
  "SELECT current_setting('wal_level'),
          current_setting('max_wal_senders'),
          current_setting('max_replication_slots');"
```

Фактический результат:

```text
replica|10|10
```

Для backup используются два replication-соединения: основное соединение `pg_basebackup` и отдельное соединение для потоковой передачи WAL. Существующей конфигурации достаточно для двух реплик и резервного копирования.

Также проверено отсутствие пользовательских tablespace:

```bash
sudo -u postgres psql -d postgres -tAc \
  "SELECT count(*) FROM pg_tablespace
   WHERE spcname NOT IN ('pg_default', 'pg_global');"
```

Получен результат:

```text
0
```

Поэтому можно безопасно использовать plain-формат без отдельного сопоставления tablespace.

#### Установка физических backup-утилит

На `ol8-backup01` устанавливаются:

```bash
sudo dnf install -y \
  postgresql-server \
  postgresql-contrib \
  cronie
```

Пакет `postgresql-server` предоставляет `pg_basebackup` и `pg_verifybackup`. Утилита `pg_waldump`, необходимая для полной проверки WAL через `pg_verifybackup`, находится в пакете `postgresql-contrib`.

Проверка версий:

```bash
pg_basebackup --version
pg_verifybackup --version
pg_waldump --version
```

Получено:

```text
pg_basebackup (PostgreSQL) 15.18
pg_verifybackup (PostgreSQL) 15.18
pg_waldump (PostgreSQL) 15.18
```

Кластер PostgreSQL на backup-сервере не инициализируется и служба PostgreSQL там не запускается. Устанавливаются только необходимые бинарные утилиты.

#### Аутентификация физического backup

Для `pg_basebackup` используется существующая роль `replicator` с правом `REPLICATION`. Пароль берётся из Ansible Vault и размещается в отдельном файле:

```text
/var/lib/pgbackup/.pgpass_physical
```

Формат файла:

```text
192.168.77.11:5432:*:replicator:<REPLICATION_PASSWORD>
```

Права файла:

```bash
sudo chown pgbackup:pgbackup /var/lib/pgbackup/.pgpass_physical
sudo chmod 0600 /var/lib/pgbackup/.pgpass_physical
```

#### Создание физической копии

Каталог хранения:

```text
/var/backups/postgresql/physical
```

Эквивалентная команда `pg_basebackup`:

```bash
sudo -u pgbackup env \
  PGPASSFILE=/var/lib/pgbackup/.pgpass_physical \
  pg_basebackup \
    --host=192.168.77.11 \
    --port=5432 \
    --username=replicator \
    --pgdata=/var/backups/postgresql/physical/base_TIMESTAMP \
    --format=plain \
    --wal-method=stream \
    --checkpoint=fast \
    --manifest-checksums=SHA256 \
    --progress \
    --verbose \
    --no-password
```

Особенности выбранной команды:

- создаётся полная копия всего PostgreSQL-кластера, а не только базы `demo`;
- WAL передаются параллельно методом `stream`;
- используется быстрый checkpoint;
- в `backup_manifest` записываются SHA256 для файлов кластера;
- постоянный replication slot не создаётся;
- PostgreSQL автоматически создаёт временный slot на время backup и удаляет его после завершения.

#### Проверка физического backup

Штатная проверка выполняется до добавления пользовательского файла `SHA256SUMS`:

```bash
pg_verifybackup --exit-on-error \
  /var/backups/postgresql/physical/base_TIMESTAMP
```

Результат:

```text
backup successfully verified
```

После штатной проверки создаётся дополнительный список SHA256 для всех файлов каталога. Поскольку `SHA256SUMS` создан после `pg_basebackup` и отсутствует в штатном `backup_manifest`, при последующих проверках он явно исключается из сравнения:

```bash
pg_verifybackup \
  --exit-on-error \
  --ignore=SHA256SUMS \
  /var/backups/postgresql/physical/base_TIMESTAMP
```

Проверка пользовательского списка контрольных сумм:

```bash
cd /var/backups/postgresql/physical/base_TIMESTAMP
sha256sum -c SHA256SUMS
```

#### Скрипт и расписание

В итоговой реализации используется скрипт:

```text
/usr/local/sbin/backup_postgresql_physical.sh
```

Скрипт:

1. создаёт временный каталог в backup-хранилище;
2. запускает `pg_basebackup`;
3. получает необходимые WAL потоковым способом;
4. проверяет backup через `pg_verifybackup`;
5. создаёт SHA256 для всех файлов;
6. только после успешных проверок переименовывает временный каталог в итоговый;
7. удаляет физические backup старше 14 дней;
8. автоматически удаляет временный каталог при ошибке.

Ручной запуск итогового скрипта:

```bash
sudo -u pgbackup \
  /usr/local/sbin/backup_postgresql_physical.sh
```

Расписание cron:

```cron
0 2 * * 0 /usr/bin/flock -n /var/lib/pgbackup/physical_backup.lock /usr/local/sbin/backup_postgresql_physical.sh >> /var/backups/postgresql/logs/physical_backup.log 2>&1
```

Физический backup создаётся каждое воскресенье в `02:00` по времени `Asia/Krasnoyarsk`.

#### Фактический результат

Создан каталог:

```text
/var/backups/postgresql/physical/base_20260719_025515
```

Параметры созданной копии:

```text
Общий размер:          320 MB
backup_manifest:       255 KB
SHA256SUMS:            106 KB
pg_verifybackup:       OK
SHA256SUMS:            OK
```

Во время выполнения PostgreSQL создал временный slot:

```text
pg_basebackup_24575
```

После завершения временный slot автоматически удалился. Проверка:

```bash
sudo -u postgres psql -tAc \
  "SELECT slot_name, slot_type, temporary, active
   FROM pg_replication_slots
   ORDER BY slot_name;"
```

В результате остались только постоянные слоты работающих реплик:

```text
pg02_slot|physical|f|t
pg03_slot|physical|f|t
```

### Реализация физического backup через Ansible

Описанная выше конфигурация фактически реализована playbook:

```text
physical_backup_pb.yaml
```

Playbook состоит из двух частей.

Первая часть выполняется на `ol8-pg01` и:

1. проверяет `wal_level`;
2. проверяет `max_wal_senders`;
3. проверяет `max_replication_slots`;
4. проверяет отсутствие пользовательских tablespace.

Вторая часть выполняется на `ol8-backup01` и:

1. проверяет переменные и пароль репликации из Ansible Vault;
2. устанавливает `postgresql-server`, `postgresql-contrib` и `cronie`;
3. проверяет системного пользователя `pgbackup`;
4. создаёт каталоги и файл `.pgpass_physical`;
5. устанавливает скрипт физического backup;
6. создаёт еженедельное расписание cron;
7. проверяет версии `pg_basebackup` и `pg_verifybackup`;
8. выводит итоговую конфигурацию.

Проверка синтаксиса:

```bash
ansible-playbook \
  -i inventory.yaml \
  physical_backup_pb.yaml \
  --syntax-check \
  --ask-vault-pass
```

Запуск:

```bash
ansible-playbook \
  -i inventory.yaml \
  physical_backup_pb.yaml \
  --ask-vault-pass \
  --ask-become-pass
```

При первом тестировании было обнаружено отсутствие `pg_waldump`. `pg_basebackup` успешно создавал копию, но `pg_verifybackup` не мог выполнить проверку WAL. Проблема устранена добавлением пакета `postgresql-contrib` в playbook.

Защитная логика скрипта при этом сработала корректно:

- незавершённый каталог не был опубликован как готовый backup;
- временные файлы были удалены;
- временный replication slot был автоматически удалён PostgreSQL;
- работа primary и двух реплик не нарушилась.

## 9.3. Резервное копирование PostgreSQL с помощью pg_probackup

### Схема

`pg_probackup` запускается пользователем `pgbackup` на `ol8-backup01` и подключается к `ol8-pg01` через PostgreSQL и SSH remote-режим.

| Параметр        | Значение                               |
| --------------- | -------------------------------------- |
| Primary         | `ol8-pg01` (`192.168.77.11`)           |
| Backup-сервер   | `ol8-backup01` (`192.168.77.20`)       |
| PGDATA          | `/var/lib/pgsql/data`                  |
| Каталог         | `/var/backups/postgresql/pg_probackup` |
| Instance        | `ol8_pg01`                             |
| Роль PostgreSQL | `backup_probackup`                     |
| Служебная база  | `backupdb`                             |
| Пользователь ОС | `pgbackup`                             |
| Backup          | FULL и DELTA                           |
| WAL             | STREAM                                 |
| Сжатие          | zlib level 1                           |
| Retention       | две FULL-цепочки                       |
| Запуск          | ручной                                 |

### Установка

На `ol8-pg01` и `ol8-backup01`:

```bash
sudo dnf install -y \
  https://repo.postgrespro.ru/pg_probackup/keys/pg_probackup-repo-centos.noarch.rpm

sudo dnf install -y pg_probackup-15
pg_probackup-15 --version
```

На обеих машинах установлена одинаковая версия:

```text
pg_probackup-15 2.5.16
```

### Роль и доступ к PostgreSQL

На `ol8-pg01`:

```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE backupdb;
CREATE ROLE backup_probackup WITH LOGIN REPLICATION;
\password backup_probackup
\c backupdb

GRANT CONNECT ON DATABASE backupdb TO backup_probackup;
GRANT USAGE ON SCHEMA pg_catalog TO backup_probackup;
GRANT pg_read_all_settings TO backup_probackup;

GRANT EXECUTE ON FUNCTION
    pg_catalog.current_setting(text),
    pg_catalog.set_config(text,text,boolean),
    pg_catalog.pg_is_in_recovery(),
    pg_catalog.pg_backup_start(text,boolean),
    pg_catalog.pg_backup_stop(boolean),
    pg_catalog.pg_create_restore_point(text),
    pg_catalog.pg_switch_wal(),
    pg_catalog.pg_last_wal_replay_lsn(),
    pg_catalog.txid_current(),
    pg_catalog.txid_current_snapshot(),
    pg_catalog.txid_snapshot_xmax(txid_snapshot),
    pg_catalog.pg_control_checkpoint()
TO backup_probackup;

\q
```

Роль имеет `LOGIN` и `REPLICATION`, но не является суперпользователем.

Перед общими правилами `pg_hba.conf` добавляются:

```text
# pg_probackup from ol8-backup01
host    backupdb      backup_probackup    192.168.77.20/32    scram-sha-256
host    replication  backup_probackup    192.168.77.20/32    scram-sha-256

host    replication  backup_probackup    0.0.0.0/0           reject
host    all          backup_probackup    0.0.0.0/0           reject
host    replication  backup_probackup    ::/0                reject
host    all          backup_probackup    ::/0                reject
```

```bash
sudo systemctl reload postgresql

sudo -u postgres psql -tAc \
  "SELECT count(*)
   FROM pg_hba_file_rules
   WHERE error IS NOT NULL;"
```

Получено `0`.

### Пароль и SSH remote-режим

На `ol8-backup01` создаётся файл `/var/lib/pgbackup/.pgpass_probackup`:

```text
192.168.77.11:5432:backupdb:backup_probackup:BACKUP_PASSWORD
192.168.77.11:5432:replication:backup_probackup:BACKUP_PASSWORD
```

`BACKUP_PASSWORD` заменяется фактическим паролем без кавычек.

```bash
sudo chown pgbackup:pgbackup \
  /var/lib/pgbackup/.pgpass_probackup

sudo chmod 0600 \
  /var/lib/pgbackup/.pgpass_probackup
```

Проверка подключения:

```bash
sudo -Hu pgbackup \
  env PGPASSFILE=/var/lib/pgbackup/.pgpass_probackup \
  psql -h 192.168.77.11 \
  -U backup_probackup \
  -d backupdb \
  -tAc \
  "SELECT current_setting('data_directory'),
          pg_is_in_recovery();"
```

Получено:

```text
/var/lib/pgsql/data|false
```

Для remote-режима на `ol8-backup01` создаётся ключ:

```bash
sudo -Hu pgbackup install -d -m 0700 \
  /var/lib/pgbackup/.ssh

sudo -Hu pgbackup ssh-keygen \
  -t ed25519 \
  -f /var/lib/pgbackup/.ssh/pg_probackup_ed25519 \
  -N ""
```

Публичный ключ добавляется на `ol8-pg01` в:

```text
/var/lib/pgsql/.ssh/authorized_keys
```

```bash
sudo chown -R postgres:postgres /var/lib/pgsql/.ssh
sudo chmod 0700 /var/lib/pgsql/.ssh
sudo chmod 0600 /var/lib/pgsql/.ssh/authorized_keys
sudo restorecon -RFv /var/lib/pgsql/.ssh
```

Проверка с `ol8-backup01`:

```bash
sudo -Hu pgbackup ssh \
  -i /var/lib/pgbackup/.ssh/pg_probackup_ed25519 \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  postgres@192.168.77.11 \
  "hostname -s; pg_probackup-15 --version"
```

Получено:

```text
ol8-pg01
pg_probackup-15 2.5.16
```

### Каталог и instance

На `ol8-backup01`:

```bash
sudo install -d \
  -o pgbackup -g pgbackup -m 0700 \
  /var/backups/postgresql/pg_probackup

sudo -Hu pgbackup pg_probackup-15 init \
  -B /var/backups/postgresql/pg_probackup
```

Добавление instance:

```bash
sudo -Hu pgbackup pg_probackup-15 add-instance \
  -B /var/backups/postgresql/pg_probackup \
  -D /var/lib/pgsql/data \
  --instance=ol8_pg01 \
  --remote-host=192.168.77.11 \
  --remote-user=postgres \
  --remote-path=/usr/bin \
  --ssh-options="-i /var/lib/pgbackup/.ssh/pg_probackup_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes"
```

Настройка:

```bash
sudo -Hu pgbackup \
  env PGPASSFILE=/var/lib/pgbackup/.pgpass_probackup \
  pg_probackup-15 set-config \
  -B /var/backups/postgresql/pg_probackup \
  --instance=ol8_pg01 \
  --remote-host=192.168.77.11 \
  --remote-user=postgres \
  --remote-path=/usr/bin \
  --ssh-options="-i /var/lib/pgbackup/.ssh/pg_probackup_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes" \
  -h 192.168.77.11 \
  -p 5432 \
  -U backup_probackup \
  -d backupdb \
  --compress-algorithm=zlib \
  --compress-level=1 \
  --retention-redundancy=2
```

### Создание и проверка backup

FULL:

```bash
sudo -Hu pgbackup \
  env PGPASSFILE=/var/lib/pgbackup/.pgpass_probackup \
  pg_probackup-15 backup \
  -B /var/backups/postgresql/pg_probackup \
  --instance=ol8_pg01 \
  -b FULL \
  --stream \
  --temp-slot
```

DELTA:

```bash
sudo -Hu pgbackup \
  env PGPASSFILE=/var/lib/pgbackup/.pgpass_probackup \
  pg_probackup-15 backup \
  -B /var/backups/postgresql/pg_probackup \
  --instance=ol8_pg01 \
  -b DELTA \
  --stream \
  --temp-slot
```

Итоговая проверка:

```bash
sudo -Hu pgbackup pg_probackup-15 validate \
  -B /var/backups/postgresql/pg_probackup \
  --instance=ol8_pg01

sudo -Hu pgbackup pg_probackup-15 show \
  -B /var/backups/postgresql/pg_probackup \
  --instance=ol8_pg01
```

Ручное применение retention:

```bash
sudo -Hu pgbackup pg_probackup-15 delete \
  -B /var/backups/postgresql/pg_probackup \
  --instance=ol8_pg01 \
  --delete-expired
```

### Результат

| ID       | Тип   | Родитель | WAL    | Статус |
| -------- | ----- | -------- | ------ | ------ |
| `TIEI14` | FULL  | —        | STREAM | OK     |
| `TIEI33` | DELTA | `TIEI14` | STREAM | OK     |

Обе копии прошли `validate`. Размер каталога составил `136M`. Retention ничего не удалил, поскольку создана одна FULL-цепочка.

Временный replication slot удалён; остались только `pg02_slot` и `pg03_slot`. Все файлы принадлежат `pgbackup`. Расписание не создавалось.


## 9.4. Резервное копирование PostgreSQL с помощью Barman

### Схема

Barman размещается на `ol8-backup01`. Полные копии передаются с `ol8-pg01` через `pg_basebackup`, а WAL непрерывно принимаются через `pg_receivewal`. SSH между серверами не требуется.

| Параметр      | Значение                         |
| ------------- | -------------------------------- |
| Primary       | `ol8-pg01` (`192.168.77.11`)     |
| Backup-сервер | `ol8-backup01` (`192.168.77.20`) |
| PostgreSQL    | `15`                             |
| Каталог       | `/var/backups/postgresql/barman` |
| Метод backup  | `postgres`                       |
| Передача WAL  | `streaming_archiver`             |
| Слот          | `barman_slot`                    |
| Retention     | две полные копии                 |
| Запуск backup | ручной                           |

В PostgreSQL 15 streaming-копии Barman являются полными. Нативные инкрементальные копии требуют PostgreSQL 17+. [Документация Barman](https://docs.pgbarman.org/release/3.19.0/user_guide/concepts.html)

### Подготовка PostgreSQL

Проверяются параметры:

```sql
SELECT current_setting('server_version'),
       current_setting('wal_level'),
       current_setting('max_wal_senders'),
       current_setting('max_replication_slots');
```

На стенде получено:

```text
15.18|replica|10|10
```

Используются слоты `pg02_slot` и `pg03_slot`; свободных слотов достаточно.

Создаются две роли:

```sql
CREATE ROLE backup_barman LOGIN;
\password backup_barman

CREATE ROLE streaming_barman LOGIN REPLICATION;
\password streaming_barman

GRANT pg_read_all_settings TO backup_barman;
GRANT pg_read_all_stats TO backup_barman;
GRANT pg_checkpoint TO backup_barman;

GRANT EXECUTE ON FUNCTION pg_backup_start(text, boolean)
TO backup_barman;

GRANT EXECUTE ON FUNCTION pg_backup_stop(boolean)
TO backup_barman;

GRANT EXECUTE ON FUNCTION pg_switch_wal()
TO backup_barman;

GRANT EXECUTE ON FUNCTION pg_create_restore_point(text)
TO backup_barman;
```

`backup_barman` используется для управления backup, а `streaming_barman` — для `pg_basebackup` и получения WAL. Обе роли не являются суперпользователями. [Требования Barman](https://docs.pgbarman.org/release/3.19.0/user_guide/pre_requisites.html)

### Настройка доступа

Перед общими правилами `pg_hba.conf` добавляются:

```text
# Barman from ol8-backup01
host    postgres       backup_barman       192.168.77.20/32    scram-sha-256
host    replication    streaming_barman    192.168.77.20/32    scram-sha-256

host    all            backup_barman       0.0.0.0/0           reject
host    all            backup_barman       ::/0                reject

host    replication    streaming_barman    0.0.0.0/0           reject
host    all            streaming_barman    0.0.0.0/0           reject
host    replication    streaming_barman    ::/0                reject
host    all            streaming_barman    ::/0                reject
```

Конфигурация перечитывается без перезапуска:

```bash
sudo systemctl reload postgresql
```

Проверка:

```bash
sudo -u postgres psql -tAc \
  "SELECT count(*)
   FROM pg_hba_file_rules
   WHERE error IS NOT NULL;"
```

Ожидается `0`.

### Установка и файл паролей

На `ol8-backup01` подключается PGDG и устанавливается основной пакет:

```bash
sudo dnf install -y \
  https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm

sudo dnf install -y barman
```

Проверка:

```bash
barman --version
command -v pg_basebackup
command -v pg_receivewal
id barman
```

В `/var/lib/barman/.pgpass` записываются:

```text
192.168.77.11:5432:postgres:backup_barman:BACKUP_BARMAN_PASSWORD
192.168.77.11:5432:*:streaming_barman:STREAMING_BARMAN_PASSWORD
```

Значения `*_PASSWORD` заменяются фактическими паролями без кавычек.

```bash
sudo chown barman:barman /var/lib/barman/.pgpass
sudo chmod 0600 /var/lib/barman/.pgpass
```

Проверка подключений:

```bash
sudo -Hu barman \
  env PGPASSFILE=/var/lib/barman/.pgpass \
  psql -h 192.168.77.11 \
  -U backup_barman -d postgres \
  -tAc "SELECT version();"
```

```bash
sudo -Hu barman \
  env PGPASSFILE=/var/lib/barman/.pgpass \
  psql \
  "host=192.168.77.11 port=5432 user=streaming_barman dbname=postgres replication=true" \
  -c "IDENTIFY_SYSTEM"
```

### Конфигурация Barman

Создаются каталоги:

```bash
sudo install -d -o barman -g barman -m 0750 \
  /var/backups/postgresql/barman

sudo install -d -o barman -g barman -m 0750 \
  /var/log/barman
```

Основные параметры `/etc/barman.conf`:

```ini
[barman]
barman_user = barman
barman_home = /var/backups/postgresql/barman
log_file = /var/log/barman/barman.log
log_level = INFO
configuration_files_directory = /etc/barman.d
```

Конфигурация `/etc/barman.d/ol8_pg01.conf`:

```ini
[ol8_pg01]
description = PostgreSQL 15 primary

conninfo = host=192.168.77.11 port=5432 user=backup_barman dbname=postgres application_name=barman
streaming_conninfo = host=192.168.77.11 port=5432 user=streaming_barman dbname=postgres application_name=barman_receive_wal

backup_method = postgres
archiver = off
streaming_archiver = on

slot_name = barman_slot
create_slot = auto
path_prefix = /usr/bin

minimum_redundancy = 1
retention_policy = REDUNDANCY 2
wal_retention_policy = main
```

Проверка:

```bash
sudo -Hu barman barman list-servers
sudo -Hu barman barman check ol8_pg01
```

### Получение WAL и создание backup

Создание слота и запуск обслуживания:

```bash
sudo -Hu barman barman receive-wal \
  --create-slot ol8_pg01

sudo -Hu barman barman cron
```

Проверка:

```bash
sudo -Hu barman barman switch-wal \
  --force ol8_pg01

sudo -Hu barman barman check ol8_pg01
sudo -Hu barman barman status ol8_pg01
```

Первая полная копия:

```bash
sudo -Hu barman barman backup \
  --wait \
  --wait-timeout 600 \
  --name manual-full-01 \
  ol8_pg01
```

Проверка:

```bash
sudo -Hu barman barman list-backups ol8_pg01
sudo -Hu barman barman check-backup ol8_pg01 BACKUP_ID
sudo -Hu barman barman verify-backup ol8_pg01 BACKUP_ID
```

`BACKUP_ID` заменяется идентификатором из `list-backups`.

### Обслуживание

Команда `barman cron` поддерживает получение WAL и автоматически применяет retention:

```text
* * * * * barman /usr/bin/barman -q cron
```

Проверяется наличие `/etc/cron.d/barman`. Если пакет его не создал, задание добавляется вручную, после чего включается `crond`:

```bash
sudo systemctl enable --now crond
```

Пользовательские backup-скрипты не создаются. Резервные копии запускаются вручную, а получение WAL и применение retention выполняет Barman.


---


## 9.5. Резервное копирование PostgreSQL с помощью WAL-G

### Схема

WAL-G запускается пользователем `postgres` на `ol8-pg01`. Backup и WAL сжимаются и передаются по SSH на отдельный раздел `ol8-backup01`.

| Параметр              | Значение                         |
| --------------------- | -------------------------------- |
| Primary               | `ol8-pg01` (`192.168.77.11`)     |
| Backup-сервер         | `ol8-backup01` (`192.168.77.20`) |
| PGDATA                | `/var/lib/pgsql/data`            |
| Каталог хранения      | `/var/backups/postgresql/wal-g`  |
| Пользователь хранения | `walg`                           |
| Передача              | SSH                              |
| Сжатие                | zstd                             |
| Backup                | FULL и delta                     |
| Максимум delta        | 3                                |
| Retention             | две FULL-цепочки                 |
| Архивирование WAL     | `archive_command`                |
| Запуск backup         | ручной                           |

SSH-хранилище настраивается через `WALG_SSH_PREFIX`, `SSH_USERNAME` и `SSH_PRIVATE_KEY_PATH`. [Хранилища WAL-G](https://wal-g.readthedocs.io/STORAGES/)

### Подготовка хранилища и SSH

На `ol8-backup01`:

```bash
sudo useradd \
  --system \
  --create-home \
  --home-dir /var/lib/walg \
  --shell /bin/bash \
  walg

sudo passwd -l walg

sudo install -d \
  -o walg -g walg -m 0750 \
  /var/backups/postgresql/wal-g

sudo install -d \
  -o walg -g walg -m 0700 \
  /var/lib/walg/.ssh
```

На `ol8-pg01` создаётся отдельный ключ:

```bash
sudo -Hu postgres install -d -m 0700 \
  /var/lib/pgsql/.ssh

sudo -Hu postgres ssh-keygen \
  -t ed25519 \
  -f /var/lib/pgsql/.ssh/id_ed25519_walg \
  -N ""

sudo cat /var/lib/pgsql/.ssh/id_ed25519_walg.pub
```

Публичный ключ добавляется на `ol8-backup01` в:

```text
/var/lib/walg/.ssh/authorized_keys
```

Формат строки:

```text
restrict ssh-ed25519 PUBLIC_KEY postgres@ol8-pg01
```

```bash
sudo chown -R walg:walg /var/lib/walg/.ssh
sudo chmod 0600 /var/lib/walg/.ssh/authorized_keys
sudo restorecon -RFv /var/lib/walg/.ssh
```

Проверка с primary:

```bash
sudo -Hu postgres ssh \
  -i /var/lib/pgsql/.ssh/id_ed25519_walg \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new \
  walg@192.168.77.20 \
  "test -w /var/backups/postgresql/wal-g && echo SSH_STORAGE_OK"
```

### Установка и конфигурация WAL-G

Актуальная версия WAL-G загружается со страницы [официальных выпусков](https://github.com/wal-g/wal-g/releases). Для стенда выбирается PostgreSQL amd64-сборка, совместимая с Oracle Linux 8.

После загрузки архива:

```bash
tar -xzf wal-g-pg-*-amd64.tar.gz

sudo install \
  -o root -g root -m 0755 \
  wal-g-pg-*-amd64 \
  /usr/local/bin/wal-g

sudo restorecon -v /usr/local/bin/wal-g
/usr/local/bin/wal-g --version
```

Если возникает ошибка GLIBC, необходимо использовать совместимую сборку или собрать WAL-G для Oracle Linux 8.

Проверяется каталог сокета PostgreSQL:

```bash
sudo -u postgres psql -Atc \
  "SHOW unix_socket_directories;"
```

Создаётся `/var/lib/pgsql/.wal-g.yaml`:

```yaml
WALG_SSH_PREFIX: "ssh://192.168.77.20/var/backups/postgresql/wal-g"
SSH_PORT: "22"
SSH_USERNAME: "walg"
SSH_PRIVATE_KEY_PATH: "/var/lib/pgsql/.ssh/id_ed25519_walg"

WALG_COMPRESSION_METHOD: "zstd"
WALG_UPLOAD_CONCURRENCY: "4"

WALG_DELTA_MAX_STEPS: "3"
WALG_DELTA_ORIGIN: "LATEST"
WALG_PREVENT_WAL_OVERWRITE: "true"

PGHOST: "/var/run/postgresql"
PGPORT: "5432"
PGUSER: "postgres"
PGDATA: "/var/lib/pgsql/data"
```

`PGHOST` заменяется, если PostgreSQL использует другой каталог сокета.

```bash
sudo chown postgres:postgres /var/lib/pgsql/.wal-g.yaml
sudo chmod 0600 /var/lib/pgsql/.wal-g.yaml
sudo restorecon -v /var/lib/pgsql/.wal-g.yaml
```

Проверка доступа к хранилищу:

```bash
sudo -Hu postgres \
  /usr/local/bin/wal-g \
  --config /var/lib/pgsql/.wal-g.yaml \
  backup-list --pretty
```

### Архивирование WAL

Перед изменением проверяется текущая конфигурация:

```bash
sudo -u postgres psql -c \
  "SELECT current_setting('archive_mode'),
          current_setting('archive_command'),
          current_setting('archive_timeout');"
```

Barman получает WAL через `pg_receivewal`, поэтому `archive_command` может использовать WAL-G.

```bash
sudo -u postgres psql -c \
  "ALTER SYSTEM SET archive_mode = 'on';"

sudo -u postgres psql -c \
  \"ALTER SYSTEM SET archive_command =
  '/usr/local/bin/wal-g --config /var/lib/pgsql/.wal-g.yaml wal-push %p';\"

sudo -u postgres psql -c \
  "ALTER SYSTEM SET archive_timeout = '300s';"
```

Для применения `archive_mode` требуется перезапуск:

```bash
sudo systemctl restart postgresql
```

После перезапуска проверяются PostgreSQL и обе реплики:

```bash
pg_isready

sudo -u postgres psql -c \
  "SELECT application_name, state, sync_state
   FROM pg_stat_replication
   ORDER BY application_name;"
```

Проверка передачи WAL:

```bash
sudo -u postgres psql -c "SELECT pg_switch_wal();"

sudo -u postgres psql -x -c \
  "SELECT archived_count,
          failed_count,
          last_archived_wal,
          last_archived_time
   FROM pg_stat_archiver;"
```

`archived_count` должен увеличиваться, а `failed_count` — оставаться равным `0`.

### Создание backup

Первая копия создаётся полной:

```bash
sudo -Hu postgres \
  env WALG_DELTA_MAX_STEPS=0 \
  /usr/local/bin/wal-g \
  --config /var/lib/pgsql/.wal-g.yaml \
  backup-push /var/lib/pgsql/data \
  --verify
```

Следующая копия создаётся как delta:

```bash
sudo -u postgres psql -c \
  "CHECKPOINT; SELECT pg_switch_wal();"

sudo -Hu postgres \
  /usr/local/bin/wal-g \
  --config /var/lib/pgsql/.wal-g.yaml \
  backup-push /var/lib/pgsql/data \
  --verify
```

Проверка списка:

```bash
sudo -Hu postgres \
  /usr/local/bin/wal-g \
  --config /var/lib/pgsql/.wal-g.yaml \
  backup-list --pretty --detail
```

Флаг `--verify` включает проверку контрольных сумм страниц. Delta-копии создаются при `WALG_DELTA_MAX_STEPS > 0`. [Документация WAL-G для PostgreSQL](https://wal-g.readthedocs.io/PostgreSQL/)

### Проверка WAL и retention

```bash
sudo -u postgres psql -c "SELECT pg_switch_wal();"
```

```bash
sudo -Hu postgres \
  /usr/local/bin/wal-g \
  --config /var/lib/pgsql/.wal-g.yaml \
  wal-show
```

```bash
sudo -Hu postgres \
  /usr/local/bin/wal-g \
  --config /var/lib/pgsql/.wal-g.yaml \
  wal-verify integrity timeline
```

Пробный расчёт retention:

```bash
sudo -Hu postgres \
  /usr/local/bin/wal-g \
  --config /var/lib/pgsql/.wal-g.yaml \
  delete retain FULL 2
```

Применение после проверки:

```bash
sudo -Hu postgres \
  /usr/local/bin/wal-g \
  --config /var/lib/pgsql/.wal-g.yaml \
  delete retain FULL 2 --confirm
```

## 10. Удаление и восстановление базы данных

Проверяется восстановление базы `demo` из логической резервной копии, созданной в пункте 9.1. Все операции восстановления выполняются на primary `ol8-pg01`, после чего данные передаются на реплики потоковой репликацией.

### Подготовка контрольных данных и backup

На `ol8-pg01` создаётся таблица с контрольным значением. По нему после восстановления проверяется целостность данных:

```bash
sudo -u postgres psql \
  -d demo \
  -v ON_ERROR_STOP=1 \
  -c "
CREATE TABLE IF NOT EXISTS public.restore_test(marker text);
TRUNCATE public.restore_test;
INSERT INTO public.restore_test VALUES ('backup_restore_ok');
"
```

На `ol8-backup01` запускается свежий логический backup:

```bash
sudo -u pgbackup \
  /usr/local/sbin/backup_demo_logical.sh
```

Определяется последний архив, проверяются его SHA256 и структура:

```bash
sudo -Hu pgbackup bash -c '
LATEST=$(find /var/backups/postgresql/logical \
  -type f -name "demo_*.dump" \
  -printf "%T@ %p\n" |
  sort -nr |
  head -1 |
  cut -d" " -f2-)

sha256sum -c "${LATEST}.sha256"
pg_restore --list "${LATEST}" >/dev/null
echo "${LATEST}"
'
```

Проверенный архив передаётся на `ol8-pg01` под именем:

```text
/tmp/demo_restore.dump
```

Для файла устанавливаются владелец и права:

```bash
sudo chown postgres:postgres /tmp/demo_restore.dump
sudo chmod 0600 /tmp/demo_restore.dump
```

### Удаление и восстановление

Перед удалением сохраняется имя владельца базы. Затем база принудительно удаляется и создаётся заново с прежним владельцем:

```bash
DB_OWNER=$(sudo -u postgres psql \
  -d postgres \
  -tAc "
SELECT pg_get_userbyid(datdba)
FROM pg_database
WHERE datname='demo';
")

sudo -u postgres psql \
  -d postgres \
  -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE demo WITH (FORCE);"

sudo -u postgres createdb \
  --owner="${DB_OWNER}" \
  --template=template0 \
  demo
```

Данные восстанавливаются из проверенного архива:

```bash
sudo -u postgres pg_restore \
  --exit-on-error \
  --dbname=demo \
  /tmp/demo_restore.dump
```

### Проверка результата

Контрольное значение проверяется на primary и обеих репликах:

```bash
ansible postgresql_cluster \
  -i inventory.yaml \
  --become \
  --become-user postgres \
  --ask-become-pass \
  -m ansible.builtin.command \
  -a "psql -d demo -tAc \
\"SELECT marker FROM public.restore_test;\""
```

Результат:

```text
ol8_pg01 | backup_restore_ok
ol8_pg02 | backup_restore_ok
ol8_pg03 | backup_restore_ok
```

База `demo` удалена и восстановлена из логической резервной копии. Контрольные данные присутствуют на primary, синхронной и асинхронной репликах.


## 11. Настройка PostgreSQL в отказоустойчивой конфигурации

Используется кластер из primary, синхронной и асинхронной реплик:

| Узел       | Роль                 |
| ---------- | -------------------- |
| `ol8_pg01` | primary              |
| `ol8_pg02` | synchronous standby  |
| `ol8_pg03` | asynchronous standby |

### 11.1. Потоковая репликация PostgreSQL

На primary настраиваются:

```text
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 512MB
hot_standby = on
wal_log_hints = on
synchronous_commit = on
synchronous_standby_names = 'FIRST 1 (ol8_pg02)'
```

Используется роль `replicator` и два физических слота:

```text
pg02_slot — синхронная реплика
pg03_slot — асинхронная реплика
```

Реализация выполнена через Ansible.

Настройка primary:

```bash
ansible-playbook \
  -i inventory.yaml \
  replication_primary_pb.yaml \
  --ask-vault-pass \
  --ask-become-pass
```

Создание реплик через `pg_basebackup`:

```bash
ansible-playbook \
  -i inventory.yaml \
  replication_replicas_pb.yaml \
  --ask-vault-pass \
  --ask-become-pass
```

Назначение синхронного и асинхронного режимов:

```bash
ansible-playbook \
  -i inventory.yaml \
  replication_sync_pb.yaml \
  --ask-become-pass
```

Проверка выполняется на primary:

```bash
ansible ol8_pg01 \
  -i inventory.yaml \
  --become \
  --become-user postgres \
  --ask-become-pass \
  -m ansible.builtin.command \
  -a "psql -d postgres -At -F '|' -c \"
SELECT application_name,
       client_addr,
       state,
       sync_state
FROM pg_stat_replication
ORDER BY application_name;
\""
```

Результат:

```text
ol8_pg02|192.168.77.12|streaming|sync
ol8_pg03|192.168.77.13|streaming|async
```

Запись, созданная на `ol8_pg01`, также проверена на обеих репликах.

### 11.2. Кластер ETCD

ETCD используется как распределённое хранилище состояния Patroni. Кластер размещается на всех трёх узлах PostgreSQL.

Используемые порты:

```text
2379/tcp — подключения Patroni и etcdctl
2380/tcp — обмен между узлами ETCD
```

На всех узлах устанавливаются одинаковые версии `etcd` и `etcdctl`. Общий состав кластера:

```text
ol8_pg01=http://192.168.77.11:2380
ol8_pg02=http://192.168.77.12:2380
ol8_pg03=http://192.168.77.13:2380
```

Конфигурация сохраняется в /etc/etcd/etcd.conf.
Каталог данных ETCD — /var/lib/etcd.

На каждом узле задаются собственные имя и IP:

```text
ETCD_NAME=NODE_NAME
ETCD_LISTEN_PEER_URLS=http://NODE_IP:2380
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://NODE_IP:2380
ETCD_LISTEN_CLIENT_URLS=http://NODE_IP:2379,http://127.0.0.1:2379
ETCD_ADVERTISE_CLIENT_URLS=http://NODE_IP:2379

ETCD_INITIAL_CLUSTER=ol8_pg01=http://192.168.77.11:2380,ol8_pg02=http://192.168.77.12:2380,ol8_pg03=http://192.168.77.13:2380
ETCD_INITIAL_CLUSTER_TOKEN=academy-patroni
ETCD_INITIAL_CLUSTER_STATE=new
```

Значения `NODE_NAME` и `NODE_IP` заменяются параметрами соответствующего узла. Адрес узла в `ETCD_INITIAL_CLUSTER` должен совпадать с его advertised peer URL. [Документация ETCD](https://etcd.io/docs/v3.5/tutorials/how-to-setup-cluster/)

Открываются необходимые порты:

```bash
sudo firewall-cmd --permanent --add-port=2379/tcp
sudo firewall-cmd --permanent --add-port=2380/tcp
sudo firewall-cmd --reload
```

ETCD запускается на всех трёх узлах:

```bash
sudo systemctl enable --now etcd
```

Проверка состояния:

```bash
ETCDCTL_API=3 etcdctl \
  --endpoints=http://192.168.77.11:2379,http://192.168.77.12:2379,http://192.168.77.13:2379 \
  endpoint health
```

Все три endpoint должны иметь состояние `healthy`.

### 11.3. Передача кластера под управление Patroni

Patroni устанавливается на всех PostgreSQL-узлах:

```bash
sudo dnf install -y \
  https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm

sudo dnf install -y patroni patroni-etcd
```

На каждом узле создаётся `/etc/patroni/patroni.yml`. Основные параметры:

```yaml
scope: postgresql-ha
namespace: /service/
name: NODE_NAME

restapi:
  listen: NODE_IP:8008
  connect_address: NODE_IP:8008

etcd3:
  hosts:
    - 192.168.77.11:2379
    - 192.168.77.12:2379
    - 192.168.77.13:2379

bootstrap:
  dcs:
    synchronous_mode: true
    synchronous_node_count: 1
    postgresql:
      use_pg_rewind: true
      use_slots: true

postgresql:
  listen: NODE_IP:5432
  connect_address: NODE_IP:5432
  data_dir: /var/lib/pgsql/data
  bin_dir: /usr/bin

  authentication:
    superuser:
      username: postgres
      password: POSTGRES_PASSWORD
    replication:
      username: replicator
      password: REPLICATION_PASSWORD
```

На каждом узле заменяются:

* `NODE_NAME`;
* `NODE_IP`;
* `POSTGRES_PASSWORD`;
* `REPLICATION_PASSWORD`.

Конфигурация защищается:

```bash
sudo chown postgres:postgres /etc/patroni/patroni.yml
sudo chmod 0600 /etc/patroni/patroni.yml
```

Для Patroni REST API открывается порт:

```bash
sudo firewall-cmd --permanent --add-port=8008/tcp
sudo firewall-cmd --reload
```

Передача существующего кластера выполняется в период обслуживания. Обычная служба PostgreSQL останавливается и отключается, поскольку дальнейший запуск PostgreSQL выполняет Patroni.

Сначала на `ol8_pg01`:

```bash
sudo systemctl disable --now postgresql
sudo systemctl enable --now patroni
```

После появления Leader аналогично подключаются `ol8_pg02` и `ol8_pg03`:

```bash
sudo systemctl disable --now postgresql
sudo systemctl enable --now patroni
```

Проверка кластера:

```bash
patronictl \
  -c /etc/patroni/patroni.yml \
  list
```

Проверяемое состояние:

```text
ol8_pg01 — Leader
ol8_pg02 — Sync Standby
ol8_pg03 — Replica
```

После перехода под управление Patroni параметры синхронной репликации и роли узлов хранятся в DCS. Повторно запускать `replication_sync_pb.yaml` нельзя. Управление кластером выполняется через `patronictl`.


## 12. Смена ролей узлов PostgreSQL

Смена ролей выполняется средствами Patroni. Для исправного кластера применяется плановый `switchover`: текущий Leader корректно понижается до Replica, а выбранная реплика становится новым Leader.

`failover` используется только при отказе Leader или неисправном состоянии кластера.

### Проверка перед переключением

Проверяется состояние всех узлов:

```bash
patronictl \
  -c /etc/patroni/patroni.yml \
  list
```


### Переключение на ol8_pg02

Роль Leader передаётся с `ol8_pg01` на синхронную реплику `ol8_pg02`:

```bash
patronictl \
  -c /etc/patroni/patroni.yml \
  switchover postgresql-ha \
  --leader ol8_pg01 \
  --candidate ol8_pg02 \
  --force
```

Проверяется новое состояние:

```bash
patronictl \
  -c /etc/patroni/patroni.yml \
  list
```

После переключения:

```text
ol8_pg02 — Leader
ol8_pg01 — Replica
ol8_pg03 — Replica
```

### Проверка записи на новом Leader

На `ol8_pg02` создаётся контрольная запись:

```bash
ansible ol8_pg02 \
  -i inventory.yaml \
  --become \
  --become-user postgres \
  --ask-become-pass \
  -m ansible.builtin.command \
  -a "psql -d demo -v ON_ERROR_STOP=1 -c \"
INSERT INTO public.replication_test(source)
VALUES ('ol8_pg02_after_switchover');
\""
```

Наличие записи проверяется на всех узлах:

```bash
ansible postgresql_cluster \
  -i inventory.yaml \
  --become \
  --become-user postgres \
  --ask-become-pass \
  -m ansible.builtin.command \
  -a "psql -d demo -tAc \"
SELECT source
FROM public.replication_test
WHERE source='ol8_pg02_after_switchover';
\""
```

Контрольная запись должна присутствовать на новом Leader и обеих репликах.

### Возврат исходного Leader

После проверки роль Leader возвращается на `ol8_pg01`:

```bash
patronictl \
  -c /etc/patroni/patroni.yml \
  switchover postgresql-ha \
  --leader ol8_pg02 \
  --candidate ol8_pg01 \
  --force
```

Итоговая проверка:

```bash
patronictl \
  -c /etc/patroni/patroni.yml \
  list
```

Дополнительно проверяется режим PostgreSQL на каждом узле:

```bash
ansible postgresql_cluster \
  -i inventory.yaml \
  --become \
  --become-user postgres \
  --ask-become-pass \
  -m ansible.builtin.command \
  -a "psql -d postgres -tAc \
\"SELECT pg_is_in_recovery();\""
```

### Результат

После первого `switchover` узел `ol8_pg02` становится Leader, а `ol8_pg01` — Replica. Запись, созданная на новом Leader, передаётся на остальные узлы.

После обратного переключения исходные роли восстанавливаются:

```text
ol8_pg01 — Leader
ol8_pg02 — Sync Standby
ol8_pg03 — Replica
```


## 13. Настройка PgBouncer

PgBouncer устанавливается на всех трёх PostgreSQL-узлах и подключается к локальному PostgreSQL на порту `5432`.

После настройки VIP клиенты будут обращаться к текущему Leader через:

```text
192.168.77.10:6432
```

VIP будет находиться только на узле Patroni с ролью Leader, поэтому PgBouncer не направит запись на реплику.

### Установка

На `ol8_pg01`, `ol8_pg02` и `ol8_pg03`:

```bash
sudo dnf install -y pgbouncer
```

Проверка:

```bash
pgbouncer --version
```

### Конфигурация

На всех узлах создаётся одинаковый `/etc/pgbouncer/pgbouncer.ini`:

```ini
[databases]
demo = host=127.0.0.1 port=5432 dbname=demo

[pgbouncer]
listen_addr = *
listen_port = 6432

auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt

pool_mode = transaction
max_client_conn = 200
default_pool_size = 20

ignore_startup_parameters = extra_float_digits
```

Режим `transaction` возвращает серверное соединение в пул после завершения транзакции. PgBouncer принимает до 200 клиентских соединений, используя ограниченный пул подключений к PostgreSQL.

### Настройка пользователей

В `DB_USER` указывается роль PostgreSQL, через которую приложение подключается к базе `demo`.

SCRAM-хеш извлекается на primary:

```bash
sudo -u postgres psql \
  -d postgres \
  -At \
  -c "
SELECT '\"' || rolname || '\" \"' || rolpassword || '\"'
FROM pg_authid
WHERE rolname='DB_USER';
"
```

Полученная строка добавляется в `/etc/pgbouncer/userlist.txt` на всех трёх узлах:

```text
"DB_USER" "SCRAM-SHA-256$..."
```

Значение `DB_USER` заменяется фактическим именем роли.

SCRAM-секрет в `userlist.txt` должен совпадать с секретом роли PostgreSQL. [Документация PgBouncer](https://www.pgbouncer.org/config.html)

Устанавливаются права:

```bash
sudo chown pgbouncer:pgbouncer \
  /etc/pgbouncer/pgbouncer.ini \
  /etc/pgbouncer/userlist.txt

sudo chmod 0640 /etc/pgbouncer/pgbouncer.ini
sudo chmod 0600 /etc/pgbouncer/userlist.txt
```

### Запуск

Открывается порт PgBouncer:

```bash
sudo firewall-cmd \
  --permanent \
  --add-port=6432/tcp

sudo firewall-cmd --reload
```

Служба запускается на всех узлах:

```bash
sudo systemctl enable --now pgbouncer
```

Проверяется состояние:

```bash
sudo systemctl is-active pgbouncer
```

### Проверка подключения

На текущем Leader выполняется подключение через PgBouncer:

```bash
psql \
  -h 127.0.0.1 \
  -p 6432 \
  -U DB_USER \
  -d demo \
  -W \
  -c "
SELECT current_database(),
       current_user,
       pg_is_in_recovery();
"
```

Для Leader ожидается:

```text
demo|DB_USER|false
```

### Результат

PgBouncer принимает клиентские подключения на порту `6432` и передаёт их локальному PostgreSQL через transaction pool. Пароли пользователей хранятся в виде SCRAM-секретов.

После настройки Keepalived приложения должны использовать единый адрес:

```text
192.168.77.10:6432
```

Практическая проверка через VIP выполняется после пункта 14. Сейчас пункт описывает порядок настройки.


## 14. Настройка VIP с помощью Keepalived

Keepalived предоставляет единый виртуальный адрес:

```text
192.168.77.10
```

Приложения подключаются к PostgreSQL через PgBouncer:

```text
192.168.77.10:6432
```

VIP должен находиться только на текущем Patroni Leader и автоматически переноситься после смены ролей.

### Установка

На `ol8_pg01`, `ol8_pg02` и `ol8_pg03`:

```bash
sudo dnf install -y keepalived curl
```

Определяется сетевой интерфейс лабораторной сети:

```bash
ip -br address
```

В дальнейшей конфигурации `INTERFACE` заменяется найденным именем интерфейса.

### Проверка роли Patroni

На всех узлах создаётся `/etc/keepalived/check_patroni_primary.sh`:

```bash
#!/usr/bin/env bash

/usr/bin/curl \
  -fsS \
  --max-time 1 \
  http://127.0.0.1:8008/primary \
  >/dev/null
```

Endpoint `/primary` возвращает HTTP 200 только на работающем primary, который владеет блокировкой Leader в Patroni. [Patroni REST API](https://patroni.readthedocs.io/en/latest/rest_api.html)

Устанавливаются права:

```bash
sudo chown root:root \
  /etc/keepalived/check_patroni_primary.sh

sudo chmod 0755 \
  /etc/keepalived/check_patroni_primary.sh
```

Проверка на каждом узле:

```bash
sudo /etc/keepalived/check_patroni_primary.sh
echo $?
```

На Leader возвращается `0`, на репликах — ненулевой код.

### Конфигурация Keepalived

На каждом узле создаётся `/etc/keepalived/keepalived.conf`:

```text
global_defs {
    router_id NODE_NAME
    script_user root
    enable_script_security
}

vrrp_script check_patroni_primary {
    script "/etc/keepalived/check_patroni_primary.sh"
    interval 2
    timeout 2
    fall 2
    rise 2
    weight 0
}

vrrp_instance VI_POSTGRESQL {
    state BACKUP
    interface INTERFACE
    virtual_router_id 51
    priority PRIORITY
    advert_int 1

    unicast_src_ip NODE_IP

    unicast_peer {
        PEER_IP_1
        PEER_IP_2
    }

    virtual_ipaddress {
        192.168.77.10/24 dev INTERFACE
    }

    track_script {
        check_patroni_primary
    }
}
```

Параметры узлов:

| Узел       | `NODE_IP`       | `PRIORITY` | `unicast_peer` |
| ---------- | --------------- | ---------: | -------------- |
| `ol8_pg01` | `192.168.77.11` |        150 | `.12`, `.13`   |
| `ol8_pg02` | `192.168.77.12` |        140 | `.11`, `.13`   |
| `ol8_pg03` | `192.168.77.13` |        130 | `.11`, `.12`   |

Дополнительно заменяются:

* `NODE_NAME` — имя текущего узла;
* `INTERFACE` — сетевой интерфейс лабораторной сети;
* `PEER_IP_1` и `PEER_IP_2` — полные адреса двух остальных узлов.

При `weight 0` два последовательных сбоя проверки переводят VRRP instance в состояние `FAULT`. Поэтому реплики не могут получить VIP.

### Запуск

На всех узлах разрешается VRRP:

```bash
sudo firewall-cmd \
  --permanent \
  --add-protocol=vrrp

sudo firewall-cmd --reload
```

Проверяется синтаксис конфигурации:

```bash
sudo keepalived \
  -t \
  -f /etc/keepalived/keepalived.conf
```

После успешной проверки запускается служба:

```bash
sudo systemctl enable --now keepalived
```

### Проверка VIP

Размещение VIP проверяется на всех узлах:

```bash
ansible postgresql_cluster \
  -i inventory.yaml \
  -m ansible.builtin.shell \
  -a "ip -4 -br address |
grep '192.168.77.10' || true"
```

Адрес должен отображаться только на текущем Patroni Leader.

Проверка подключения через VIP и PgBouncer:

```bash
psql \
  -h 192.168.77.10 \
  -p 6432 \
  -U DB_USER \
  -d demo \
  -W \
  -c "
SELECT inet_server_addr(),
       current_database(),
       pg_is_in_recovery();
"
```

Для Leader значение `pg_is_in_recovery()` должно быть `false`.

### Проверка переноса VIP

Выполняется `switchover` из пункта 12, после чего повторно проверяется размещение адреса:

```bash
ansible postgresql_cluster \
  -i inventory.yaml \
  -m ansible.builtin.shell \
  -a "ip -4 -br address |
grep '192.168.77.10' || true"
```

Подключение приложения не изменяется:

```text
192.168.77.10:6432
```

### Результат

VIP `192.168.77.10` находится только на текущем Patroni Leader. После `switchover` Keepalived удаляет адрес со старого Leader и назначает его новому.

Клиенты продолжают использовать один адрес независимо от того, какой PostgreSQL-узел выполняет роль Leader.

Практическая проверка возможна после настройки Patroni и PgBouncer. Сейчас раздел описывает порядок реализации.

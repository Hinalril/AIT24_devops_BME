# Этап 1. Развёртывание PostgreSQL

## Шаг 1. Подготовка платформы виртуализации

### Цель

Подготовить среду для развёртывания виртуальной машины с Oracle Linux 8. В качестве платформы виртуализации используется Microsoft Hyper-V, поскольку основной компьютер работает под управлением Windows 11 Professional.

### Характеристики компьютера

- Операционная система: Windows 11 Professional, 64-bit
- Процессор: AMD Ryzen 7 5700G
- Физические ядра: 8
- Логические процессоры: 16
- Оперативная память: 16 ГБ
- Гипервизор: Microsoft Hyper-V
- Каталог лабораторного стенда: `H:\DevOpsLab`

Для первой виртуальной машины запланированы следующие ресурсы:

- 2 виртуальных процессора;
- 3 ГБ оперативной памяти;
- системный виртуальный диск размером 30 ГБ;
- дополнительный виртуальный диск размером 30 ГБ;
- операционная система Oracle Linux 8.10.

Дополнительный диск будет использован для выполнения задания по настройке LVM и размещения данных PostgreSQL.

## Установка Hyper-V

Для запуска виртуальных машин был установлен встроенный компонент Microsoft Hyper-V.

Установка выполнялась в PowerShell с правами администратора:

```powershell
Enable-WindowsOptionalFeature `
    -Online `
    -FeatureName Microsoft-Hyper-V `
    -All
```

Проверка работоспособности командой virtmgmt.msc.


## Настройка виртуальной сети

Для лабораторного стенда создан отдельный внутренний виртуальный коммутатор Hyper-V с именем `DevOpsLab`.

Для виртуальных машин выделена подсеть:

```text
192.168.77.0/24
```

Используются следующие адреса:

| Назначение | Адрес |
|---|---|
| Windows-хост и шлюз | `192.168.77.1` |
| Будущий виртуальный IP кластера | `192.168.77.10` |
| Первая VM | `192.168.77.11` |
| Вторая VM | `192.168.77.12` |
| Третья VM | `192.168.77.13` |
| Четвёртая VM | `192.168.77.20` |

Виртуальный коммутатор был создан командой:

```powershell
New-VMSwitch `
    -SwitchName "DevOpsLab" `
    -SwitchType Internal
```

Сетевому интерфейсу Windows был назначен адрес шлюза:

```powershell
$adapter = Get-NetAdapter -Name "vEthernet (DevOpsLab)"

New-NetIPAddress `
    -InterfaceIndex $adapter.ifIndex `
    -IPAddress 192.168.77.1 `
    -PrefixLength 24
```

Для выхода виртуальных машин в интернет настроена трансляция сетевых адресов:

```powershell
New-NetNat `
    -Name "DevOpsLabNAT" `
    -InternalIPInterfaceAddressPrefix 192.168.77.0/24
```

## Проверка виртуальной сети

Для проверки были выполнены команды:

```powershell
Get-VMSwitch -Name "DevOpsLab"

Get-NetIPAddress `
    -InterfaceAlias "vEthernet (DevOpsLab)" `
    -AddressFamily IPv4

Get-NetNat -Name "DevOpsLabNAT"
```

Получены следующие результаты:

- виртуальный коммутатор `DevOpsLab` создан;
- тип коммутатора: `Internal`;
- интерфейсу Windows назначен адрес `192.168.77.1/24`;
- NAT `DevOpsLabNAT` использует сеть `192.168.77.0/24`.


## Создание виртуальной машины

В диспетчере Hyper-V была создана виртуальная машина со следующими параметрами:

| Параметр | Значение |
|---|---|
| Имя | `ol8-pg01` |
| Поколение | Generation 2 |
| Виртуальные процессоры | 2 |
| Оперативная память | 3072 МБ |
| Динамическая память | Отключена |
| Системный диск | 30 ГБ, VHDX |
| Диск PostgreSQL | 30 ГБ, VHDX |
| Виртуальный коммутатор | `DevOpsLab` |
| Автоматические checkpoints | Отключены |

Для поддержки загрузки Oracle Linux был включён Secure Boot с шаблоном:

```text
Microsoft UEFI Certificate Authority
```

В качестве установочного носителя подключён образ:

```text
OracleLinux-R8-U10-x86_64-dvd.iso
```

## Установка Oracle Linux 8.10

Для экономии ресурсов выбран вариант установки `Minimal Install`.

Во время установки был создан пользователь:

```text
ansible
```

Пользователю предоставлены административные права через группу `wheel`.
Учётная запись root оставлена заблокированной.

### Настройка сети

Сетевому интерфейсу `eth0` назначены следующие параметры:

| Параметр | Значение |
|---|---|
| IP-адрес | `192.168.77.11` |
| Маска | `255.255.255.0` |
| Шлюз | `192.168.77.1` |
| DNS | `1.1.1.1, 8.8.8.8` |
| Hostname | `ol8-pg01.devops.test` |

### Выбор диска

Установщик обнаружил два виртуальных диска:

- `/dev/sda`: системный диск;
- `/dev/sdb`: дополнительный диск для LVM и PostgreSQL.

Для установки Oracle Linux был выбран только `/dev/sda`. Диск `/dev/sdb`
оставлен пустым и неразмеченным.

Для системного диска использована автоматическая LVM-разметка.

## Проверка установленной системы

После установки были выполнены команды:

```bash
cat /etc/oracle-release
hostnamectl --static
ip -br address
ip route
systemctl is-active sshd
```

Получены следующие результаты:

- установлена Oracle Linux Server 8.10;
- hostname: `ol8-pg01.devops.test`;
- интерфейс `eth0` находится в состоянии `UP`;
- назначен адрес `192.168.77.11/24`;
- маршрут по умолчанию проходит через `192.168.77.1`;
- служба SSH находится в состоянии `active`.

## Исходная конфигурация LVM

Для проверки дисков и LVM выполнены команды:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
sudo pvs
sudo vgs
sudo lvs
```

Системная конфигурация:

| Объект | Значение |
|---|---|
| Системный диск | `/dev/sda`, 30 ГБ |
| EFI-раздел | `/dev/sda1`, 600 МБ |
| Раздел `/boot` | `/dev/sda2`, 1 ГБ |
| LVM-раздел | `/dev/sda3`, около 28,4 ГБ |
| Системная VG | `ol_ol8-pg01` |
| Корневой LV | `root`, около 26,3 ГБ |
| Swap LV | `swap`, около 2,1 ГБ |
| Свободное место в VG | 0 |
| Дополнительный диск | `/dev/sdb`, 30 ГБ, не размечен |

Дополнительный диск `/dev/sdb` будет разделён между расширением системной
VG и отдельной VG для PostgreSQL.

## Проверка SSH-подключения

С Windows-хоста выполнена проверка порта SSH:

```powershell
Test-NetConnection 192.168.77.11 -Port 22
```

После этого выполнено подключение:

```powershell
ssh ansible@192.168.77.11
```

Подключение прошло успешно. Проверка пользователя и hostname:

```bash
hostname
whoami
```

Результат:

```text
ol8-pg01.devops.test
ansible
```


## Настройка LVM

### Цель

Для данных PostgreSQL необходимо использовать отдельный логический том. Также требуется расширить корневой том операционной системы и оставить свободное место для создания LVM-снимка.

Настройка выполнена с помощью Ansible из среды WSL 2. Использовались:

- inventory-файл `ansible/inventory.yaml`;
- playbook `ansible/lvm_pb.yaml`;
- коллекции `community.general` и `ansible.posix`;
- дополнительный виртуальный диск `/dev/sdb` размером 30 ГБ.

### Исходное состояние дисков

До запуска playbook системный диск `/dev/sda` уже использовался Oracle Linux. Дополнительный диск `/dev/sdb` не содержал разделов и файловых систем:

```text
sdb  30G  disk
```

Системная группа томов имела имя `ol_ol8-pg01`. Всё свободное место в ней было занято логическими томами `root` и `swap`.

### Схема разметки дополнительного диска

На диске `/dev/sdb` создана таблица разделов GPT.

| Раздел | Размер | Назначение |
|---|---:|---|
| `/dev/sdb1` | 25 ГБ | Группа томов PostgreSQL |
| `/dev/sdb2` | 5 ГБ | Расширение системной группы томов |

На разделе `/dev/sdb1` создана группа томов `vg_postgres`. В ней создан логический том `lv_pgdata` размером 20 ГБ.

Оставшиеся приблизительно 5 ГБ свободного пространства предназначены для последующего создания LVM-снимка.

Раздел `/dev/sdb2` добавлен в системную группу `ol_ol8-pg01`. Всё полученное свободное пространство передано корневому логическому тому `root`.

### Запуск автоматизации

Реализована автоматизация через файлы yaml: inventory.yaml и lvm_pb.yaml.

Заход в wsl и папку, в которой лежат inventory.yaml и lvm_pb.yaml.

Перед запуском была выполнена проверка синтаксиса:

```bash
ansible-playbook -i inventory.yaml lvm_pb.yaml --syntax-check
```

Настройка LVM выполнена командой:

```bash
ansible-playbook -i inventory.yaml lvm_pb.yaml --ask-become-pass
```

Пароль `sudo` пользователя `ansible` передавался интерактивно и не сохранялся в файлах проекта.

Playbook выполнил следующие операции:

1. Установил пакеты `parted`, `lvm2` и `xfsprogs`.
2. Создал таблицу разделов GPT.
3. Создал разделы `/dev/sdb1` и `/dev/sdb2`.
4. Добавил `/dev/sdb2` в системную группу томов.
5. Расширил корневой логический том и файловую систему XFS.
6. Создал группу томов `vg_postgres`.
7. Создал логический том `lv_pgdata`.
8. Создал на нём файловую систему XFS.
9. Подключил том в каталог `/var/lib/pgsql`.
10. Добавил постоянное монтирование в `/etc/fstab`.

### Полученный результат

После выполнения playbook получена следующая конфигурация:

| Объект | Результат |
|---|---|
| Системная VG | `ol_ol8-pg01` |
| Корневой LV | `root`, 31,28 ГБ |
| VG PostgreSQL | `vg_postgres`, около 25 ГБ |
| LV PostgreSQL | `lv_pgdata`, 20 ГБ |
| Свободное место в `vg_postgres` | около 5 ГБ |
| Файловая система | XFS |
| Точка монтирования | `/var/lib/pgsql` |

Том PostgreSQL подключён следующим образом:

```text
/dev/mapper/vg_postgres-lv_pgdata on /var/lib/pgsql type xfs
```

### Проверка идемпотентности

Playbook был запущен повторно. Итог повторного выполнения:

```text
PLAY RECAP *************************************************************************************************************
ol8_pg01                   : ok=18   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

Это подтверждает, что playbook является идемпотентным и не вносит повторные изменения в уже настроенную систему.

### 2. Создание LVM-снимка и откат изменений

Для проверки механизма LVM snapshot был создан контрольный файл:

```bash
echo "Created before snapshot" |
sudo tee /var/lib/pgsql/before_snapshot.txt

sudo sync
```

После этого создан снимок логического тома `lv_pgdata` размером 4 ГБ:

```bash
sudo lvcreate \
  --snapshot \
  --size 4G \
  --name lv_pgdata_snap \
  /dev/vg_postgres/lv_pgdata
```

После создания снимка в файловую систему внесено тестовое изменение:

```bash
echo "Created after snapshot" |
sudo tee /var/lib/pgsql/after_snapshot.txt
```

Команда `lvs` показала созданный снимок:

```text
LV               VG           LSize   Origin       Data%
lv_pgdata        vg_postgres  20.00g
lv_pgdata_snap   vg_postgres   4.00g  lv_pgdata   0.01
```

Для отката файловая система была синхронизирована и временно отключена:

```bash
sudo sync
sudo umount /var/lib/pgsql
```

Слияние снимка с исходным томом выполнено командой:

```bash
sudo lvconvert \
  --merge \
  /dev/vg_postgres/lv_pgdata_snap
```

После завершения слияния логический том снова подключён:

```bash
sudo mount /var/lib/pgsql
```

Результат отката проверен командами:

```bash
sudo ls -l /var/lib/pgsql
sudo cat /var/lib/pgsql/before_snapshot.txt
```

После восстановления файл `before_snapshot.txt` присутствовал, а созданный после снимка файл `after_snapshot.txt` отсутствовал:

```text
Rollback successful
```

Таким образом, создание LVM-снимка, внесение изменений и восстановление исходного состояния выполнены успешно. После слияния временный снимок был автоматически удалён, а выделенное под него пространство возвращено группе томов.

## 3. Настройка пользователей и sudo

Для работы с операционной системой используются не-root пользователи:

| Пользователь | Назначение | Права |
|---|---|---|
| `ansible` | Выполнение автоматизации | `sudo` через группу `wheel` |
| `dba` | Администрирование PostgreSQL | `sudo` через группу `wheel` |

Пользователь `dba` создан с помощью Ansible-playbook `users_pb.yaml`. Для него настроены:

- домашний каталог `/home/dba`;
- командная оболочка `/bin/bash`;
- членство в группе `wheel`;
- вход по SSH-ключу;
- выполнение привилегированных команд через `sudo`.

Playbook запускался командой:

```bash
ansible-playbook \
  -i inventory.yaml \
  users_pb.yaml \
  --ask-become-pass
```

Пароль пользователя `dba` установлен интерактивно непосредственно на сервере:

```bash
sudo passwd dba
```

Пароли пользователей не сохранялись в inventory или playbook.

Удалённый вход проверен командой:

```bash
ssh -i ~/.ssh/academy_ansible_ed25519 \
  dba@192.168.77.11
```

Проверка пользователя и прав:

```bash
id
sudo whoami
```

Пользователь `dba` входит в группу `wheel`, а команда `sudo whoami` возвращает:

```text
root
```

При повторном запуске playbook получен результат:

```text
PLAY RECAP *************************************************************************************************************
ol8_pg01                   : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

Подтверждает идемпотентность настройки пользователей.

## 4. Установка системных пакетов и PostgreSQL 15

Перед установкой были проверены включённые репозитории Oracle Linux:

```text
ol8_UEKR7
ol8_appstream
ol8_baseos_latest
```

Пакеты `pwgen` и `screen` отсутствовали в базовых репозиториях. Для их установки подключён репозиторий Oracle Linux `ol8_developer_EPEL` с помощью пакета:

```text
oracle-epel-release-el8
```

Установка автоматизирована playbook `packages_pb.yaml`.

Установлены следующие системные утилиты:

```text
vim-enhanced wget telnet mc nmap-ncat tcpdump autofs
nfs-utils curl pwgen cloud-utils-growpart net-tools lsof
bind-utils sysstat unzip bc sg3_utils sysfsutils nano git
glibc-langpack-ru screen
```

Для установки PostgreSQL был включён поток DNF:

```bash
dnf module enable -y postgresql:15
```

После этого установлены пакеты:

```text
postgresql-server
postgresql-contrib
```

Проверка версии показала:

```text
psql (PostgreSQL) 15.18
```

Поток PostgreSQL 15 имеет статус `[e]`, то есть включён.

Повторный запуск playbook завершился результатом:

```text
PLAY RECAP ************************************************************************************************************************************************************************
ol8_pg01                   : ok=9    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
```

Кластер базы данных на этом шаге не инициализировался, поскольку контрольные суммы должны быть включены отдельно во время выполнения `initdb`.

## 5. Инициализация и настройка PostgreSQL

Кластер PostgreSQL размещён на отдельном логическом томе:

```text
/var/lib/pgsql/data
```

Каталог принадлежит пользователю и группе `postgres`, имеет права `0700` и SELinux-контекст `postgresql_db_t`.

Инициализация и настройка автоматизированы playbook `postgresql_pb.yaml`.

Кластер инициализирован от системного пользователя `postgres`:

```bash
initdb \
  --data-checksums \
  --auth-local=peer \
  --auth-host=scram-sha-256 \
  -D /var/lib/pgsql/data
```

Параметр `--data-checksums` включает контрольные суммы страниц данных. Локальные подключения используют аутентификацию `peer`, а сетевые — `scram-sha-256`.

В `postgresql.conf` настроены параметры:

```text
listen_addresses = '*'
password_encryption = 'scram-sha-256'
```

В `pg_hba.conf` добавлено правило доступа только из лабораторной сети:

```text
host    all    all    192.168.77.0/24    scram-sha-256
```

В firewall добавлено правило, разрешающее подключения к TCP-порту 5432 только из сети `192.168.77.0/24`.

Служба PostgreSQL включена в автоматический запуск и запущена:

```text
postgresql.service
```

Проверка контрольных сумм вернула:

```text
Data checksums: on
```

Проверка состояния сервера вернула:

```text
127.0.0.1:5432 - accepting connections
```

Повторный запуск playbook завершился без изменений:

```text
PLAY RECAP *********************************************************************************************************************************************************************************************************
ol8_pg01                   : ok=12   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

Это подтверждает идемпотентность и корректность конфигурации PostgreSQL.

## 6. Загрузка Demo-базы и настройка пользователя

В качестве учебного набора данных использована база «Авиаперевозки» от Postgres Pro:

```text
https://edu.postgrespro.ru/demo-small.zip
```

Архив размером около 21 МБ содержит логический SQL-дамп. Размер восстановленной базы составляет 280 МБ.

Архив загружен командой:

```bash
wget \
  -O /tmp/demo-small.zip \
  https://edu.postgrespro.ru/demo-small.zip
```

База восстановлена от системного пользователя `postgres`:

```bash
sudo -u postgres bash -c \
  'zcat /tmp/demo-small.zip | psql -v ON_ERROR_STOP=1'
```

При первом запуске импорт остановился, поскольку база `demo` ещё не существовала. Была создана пустая база:

```bash
sudo -u postgres createdb demo
```

После этого повторное восстановление завершилось успешно.

Проверка базы показала:

```text
Название базы: demo
Размер: 280 MB
Количество аэропортов: 104
Количество основных таблиц: 8
```

Данные находятся в схеме `bookings`.

### Пользователь Demo-базы

Создана отдельная роль PostgreSQL:

```sql
CREATE ROLE demo_user LOGIN;
```

Пароль задан интерактивно командой:

```text
\password demo_user
```

Пароль не сохранялся в документации, SQL-файлах или shell history.

Пользователю выданы права на базу, схему и существующие объекты:

```sql
GRANT ALL PRIVILEGES ON DATABASE demo TO demo_user;
GRANT ALL PRIVILEGES ON SCHEMA bookings TO demo_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA bookings TO demo_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bookings TO demo_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA bookings TO demo_user;
```

Также настроены права на объекты, которые будут созданы в будущем, и поисковый путь:

```sql
ALTER ROLE demo_user
IN DATABASE demo
SET search_path = bookings, public;
```

Роль `demo_user` не является суперпользователем и имеет права только на необходимые объекты Demo-базы.

### Проверка сетевого подключения и прав

Подключение выполнено по TCP:

```bash
psql \
  -h 192.168.77.11 \
  -U demo_user \
  -d demo \
  -W
```

Проверка вернула:

```text
current_user: demo_user
current_database: demo
search_path: bookings, public
```

Пользователь успешно прочитал данные из таблицы `airports`, создал тестовую таблицу, добавил запись, прочитал её и удалил таблицу. Это подтверждает наличие прав чтения и записи.

## 7. Подключение через PgAdmin и выполнение SQL-запросов

На рабочую станцию установлена программа PgAdmin 4 версии 9.16:

```powershell
winget install --id PostgreSQL.pgAdmin --exact
```

В PgAdmin зарегистрирован сервер со следующими параметрами:

```text
Сервер: 192.168.77.11
Порт: 5432
База данных: demo
Пользователь: demo_user
```

Удалённое подключение выполнено успешно. Проверочный запрос показал:

```text
Пользователь: demo_user
База данных: demo
Версия сервера: PostgreSQL 15.18
```

Учебные запросы сохранены в файле:

```text
sql/stage_1queries.sql
```

```sql
-- Использовать схему bookings по умолчанию
SET search_path = bookings, public;


-- 1. WHERE и ORDER BY:
-- последние 20 завершённых рейсов
SELECT
    flight_no,
    departure_airport,
    arrival_airport,
    scheduled_departure,
    status
FROM flights
WHERE status = 'Arrived'
ORDER BY scheduled_departure DESC
LIMIT 20;


-- 2. GROUP BY и ORDER BY:
-- количество рейсов по каждому статусу
SELECT
    status,
    COUNT(*) AS flight_count
FROM flights
GROUP BY status
ORDER BY flight_count DESC;


-- 3. JOIN, WHERE и ORDER BY:
-- рейсы из московских аэропортов
SELECT
    f.flight_no,
    dep.airport_name AS departure_airport,
    dep.city AS departure_city,
    arr.airport_name AS arrival_airport,
    arr.city AS arrival_city,
    f.scheduled_departure,
    f.status
FROM flights AS f
JOIN airports AS dep
    ON dep.airport_code = f.departure_airport
JOIN airports AS arr
    ON arr.airport_code = f.arrival_airport
WHERE dep.airport_code IN ('SVO', 'DME', 'VKO')
ORDER BY f.scheduled_departure DESC
LIMIT 20;


-- 4. JOIN, WHERE, GROUP BY и ORDER BY:
-- десять завершённых рейсов с наибольшей выручкой
SELECT
    f.flight_id,
    f.flight_no,
    dep.city AS departure_city,
    arr.city AS arrival_city,
    f.scheduled_departure,
    COUNT(tf.ticket_no) AS tickets_sold,
    ROUND(SUM(tf.amount), 2) AS revenue
FROM flights AS f
JOIN ticket_flights AS tf
    ON tf.flight_id = f.flight_id
JOIN airports AS dep
    ON dep.airport_code = f.departure_airport
JOIN airports AS arr
    ON arr.airport_code = f.arrival_airport
WHERE f.status = 'Arrived'
GROUP BY
    f.flight_id,
    f.flight_no,
    dep.city,
    arr.city,
    f.scheduled_departure
ORDER BY revenue DESC
LIMIT 10;


-- 5. План выполнения сложного запроса
-- EXPLAIN выводит план выполнения запроса.
-- ANALYZE фактически выполняет запрос и показывает реальное время,
-- количество обработанных строк и число повторений каждого узла.
-- BUFFERS показывает обращения к страницам данных в памяти и на диске.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    f.flight_id,
    f.flight_no,
    dep.city AS departure_city,
    arr.city AS arrival_city,
    f.scheduled_departure,
    COUNT(tf.ticket_no) AS tickets_sold,
    ROUND(SUM(tf.amount), 2) AS revenue
FROM flights AS f
JOIN ticket_flights AS tf
    ON tf.flight_id = f.flight_id
JOIN airports AS dep
    ON dep.airport_code = f.departure_airport
JOIN airports AS arr
    ON arr.airport_code = f.arrival_airport
WHERE f.status = 'Arrived'
GROUP BY
    f.flight_id,
    f.flight_no,
    dep.city,
    arr.city,
    f.scheduled_departure
ORDER BY revenue DESC
LIMIT 10;
```

В запросах использованы требуемые конструкции:

- `WHERE` — фильтрация завершённых рейсов;
- `ORDER BY` — сортировка по времени и выручке;
- `GROUP BY` — группировка рейсов по статусам;
- `JOIN` — соединение рейсов, аэропортов и билетов;
- агрегатные функции `COUNT` и `SUM`;
- `EXPLAIN (ANALYZE, BUFFERS)` — анализ фактического плана выполнения.


## Финальная проверка после перезагрузки

Для проверки постоянства конфигурации виртуальная машина была перезагружена.

После загрузки с Windows проверена доступность сетевых служб:

```PowerShell
Test-NetConnection 192.168.77.11 -Port 22 |
    Select-Object ComputerName,RemotePort,TcpTestSucceeded
```
```PowerShell
Test-NetConnection 192.168.77.11 -Port 5432 |
    Select-Object ComputerName,RemotePort,TcpTestSucceeded
```


| Порт | Назначение | Результат |
|---:|---|---|
| 22 | SSH | `TcpTestSucceeded: True` |
| 5432 | PostgreSQL | `TcpTestSucceeded: True` |

### Проверка LVM

Логический том PostgreSQL автоматически подключился после перезагрузки:

```Bash
findmnt /var/lib/pgsql
```

```text
/dev/mapper/vg_postgres-lv_pgdata
/var/lib/pgsql
xfs
```

Использование файловых систем:
```Bash
df -hT / /var/lib/pgsql
```

```text
Корневая файловая система: 32 ГБ, использовано 26%
Том PostgreSQL:            20 ГБ, использовано 4%
```

Итоговая конфигурация LVM:
```Bash
sudo vgs
sudo lvs
```

```text
VG ol_ol8-pg01:
  root — 31,28 ГБ
  swap — 2,12 ГБ

VG vg_postgres:
  lv_pgdata — 20 ГБ
  свободно — около 5 ГБ
```

Временный LVM-снимок после успешного rollback отсутствует, а выделенное под него пространство возвращено группе `vg_postgres`.

### Проверка PostgreSQL

Служба PostgreSQL включена в автозапуск и работает:

```text
systemctl is-enabled postgresql: enabled
systemctl is-active postgresql:  active
```

Проверочный SQL-запрос

```Bash
sudo -u postgres psql -d demo -tAc \
  "SELECT current_database(),
          current_setting('data_checksums'),
          (SELECT count(*) FROM bookings.airports);"
```

 вернул:

```text
demo|on|104
```

Это подтверждает:

- база `demo` доступна;
- контрольные суммы страниц данных включены;
- в таблице аэропортов находятся 104 записи.

Правило firewall после перезагрузки также сохранилось:
```Bash
sudo firewall-cmd --query-rich-rule='rule family="ipv4" source address="192.168.77.0/24" port port="5432" protocol="tcp" accept'
```

```text
192.168.77.0/24 → TCP 5432: yes
```

Таким образом, LVM, PostgreSQL, Demo-база, firewall и удалённый доступ корректно восстанавливаются после перезагрузки.
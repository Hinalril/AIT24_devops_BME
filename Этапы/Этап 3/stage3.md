# Этап 3. Мониторинг, pgAdmin и проверка сети

## 15. Мониторинг Linux и PostgreSQL

Для визуализации используется Grafana. Метрики собираются двумя независимыми способами:

1. Prometheus с Linux- и PostgreSQL-exporter.
2. Zabbix с Agent 2 и PostgreSQL-плагином.

### Схема

| Компонент           | Размещение     |        Порт |
| ------------------- | -------------- | ----------: |
| Prometheus          | `ol8_backup01` |        9090 |
| Grafana             | `ol8_backup01` |        3000 |
| Zabbix Server и Web | `ol8_backup01` | 10051, 8080 |
| Node Exporter       | все четыре VM  |        9100 |
| Postgres Exporter   | `ol8_pg01–03`  |        9187 |
| Zabbix Agent 2      | все четыре VM  |       10050 |

На `ol8_backup01` одновременно размещаются Prometheus, Grafana, Zabbix, локальная база Zabbix, Nginx, Docker и pgAdmin. Для стабильной работы максимальный объём RAM этой VM увеличивается до `4 GB`.

### Подготовка PostgreSQL

На текущем Patroni Leader создаются отдельные роли мониторинга:

```sql
CREATE ROLE postgres_exporter LOGIN;
\password postgres_exporter
GRANT CONNECT ON DATABASE postgres TO postgres_exporter;
GRANT pg_monitor TO postgres_exporter;

CREATE ROLE zbx_monitor LOGIN;
\password zbx_monitor
GRANT CONNECT ON DATABASE postgres TO zbx_monitor;
GRANT pg_monitor TO zbx_monitor;
```

Роли `pg_monitor` достаточно для получения системных метрик без прав суперпользователя. [Postgres Exporter](https://github.com/prometheus-community/postgres_exporter), [Zabbix PostgreSQL template](https://www.zabbix.com/integrations/postgresql)

На всех трёх PostgreSQL-узлах в `pg_hba.conf` разрешаются локальные подключения Postgres Exporter и Zabbix Agent:

```text
host    postgres    postgres_exporter    127.0.0.1/32    scram-sha-256
host    postgres    zbx_monitor          127.0.0.1/32    scram-sha-256
```

Конфигурация перечитывается на всех PostgreSQL-узлах:


```bash
ansible postgresql_cluster \
  -i inventory.yaml \
  --become \
  --become-user postgres \
  --ask-become-pass \
  -m ansible.builtin.command \
  -a 'psql -d postgres -c "SELECT pg_reload_conf();"'
```

Для статистики SQL-запросов через конфигурацию Patroni добавляется:

```yaml
postgresql:
  parameters:
    shared_preload_libraries: pg_stat_statements
```

Сохраняются уже существующие значения `shared_preload_libraries`. После последовательного перезапуска узлов расширение создаётся на Leader:

```bash
sudo -u postgres psql -d postgres \
  -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

sudo -u postgres psql -d demo \
  -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

Проверка:

```sql
SHOW shared_preload_libraries;
SELECT extname FROM pg_extension
WHERE extname='pg_stat_statements';
```

### Prometheus и exporters

На всех четырёх VM устанавливается Node Exporter как системная служба:

```text
пользователь: node_exporter
бинарный файл: /usr/local/bin/node_exporter
служба: node_exporter.service
порт: 9100
```

На трёх PostgreSQL-узлах аналогично устанавливается Postgres Exporter:

```text
пользователь: postgres_exporter
бинарный файл: /usr/local/bin/postgres_exporter
служба: postgres_exporter.service
порт: 9187
```

Для подключения используется `/etc/postgres_exporter/postgres_exporter.env`:

```ini
DATA_SOURCE_URI=127.0.0.1:5432/postgres?sslmode=disable
DATA_SOURCE_USER=postgres_exporter
DATA_SOURCE_PASS_FILE=/etc/postgres_exporter/password
```

Файл с паролем защищается:

```bash
sudo chown postgres_exporter:postgres_exporter \
  /etc/postgres_exporter/password

sudo chmod 0600 \
  /etc/postgres_exporter/password
```

Службы запускаются и добавляются в автозагрузку:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
sudo systemctl enable --now postgres_exporter
```

Проверка:

```bash
curl -fsS http://127.0.0.1:9100/metrics >/dev/null
curl -fsS http://127.0.0.1:9187/metrics >/dev/null
```

Порты `9100` и `9187` разрешаются только для `192.168.77.20`.

### Настройка Prometheus

На `ol8_backup01` устанавливается Prometheus `3.13.1 LTS` из официального архива. Создаются:

```text
/etc/prometheus/prometheus.yml
/var/lib/prometheus
/etc/systemd/system/prometheus.service
```

Основная конфигурация:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - 127.0.0.1:9090

  - job_name: linux
    static_configs:
      - targets:
          - 192.168.77.11:9100
          - 192.168.77.12:9100
          - 192.168.77.13:9100
          - 192.168.77.20:9100

  - job_name: postgresql
    static_configs:
      - targets:
          - 192.168.77.11:9187
          - 192.168.77.12:9187
          - 192.168.77.13:9187
```

Структура соответствует стандартной схеме сбора Node Exporter. [Документация Prometheus](https://prometheus.io/docs/guides/node-exporter/)

Проверка и запуск:

```bash
promtool check config /etc/prometheus/prometheus.yml
sudo systemctl enable --now prometheus
```

В интерфейсе Prometheus проверяется страница:

```text
http://192.168.77.20:9090/targets
```

Все targets должны иметь состояние `UP`.

### Grafana

На `ol8_backup01` подключается официальный RPM-репозиторий Grafana:

```bash
sudo tee /etc/yum.repos.d/grafana.repo >/dev/null <<'EOF'
[grafana]
name=Grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

sudo dnf install -y grafana
sudo systemctl enable --now grafana-server
```

В интерфейсе:

```text
http://192.168.77.20:3000
```

После первого входа меняется пароль `admin`. Добавляется источник данных:

```text
Type: Prometheus
URL: http://127.0.0.1:9090
```

Импортируются или создаются два dashboard:

* Linux — CPU, RAM, диски, сеть и load average;
* PostgreSQL — подключения, транзакции, блокировки, репликация и состояние базы.

### Zabbix

На `ol8_backup01` устанавливаются Zabbix Server 7.4, Web-интерфейс, Agent 2 и локальная PostgreSQL-база для хранения метрик:

```bash
sudo dnf install -y \
  https://repo.zabbix.com/zabbix/7.4/release/oracle/8/noarch/zabbix-release-latest-7.4.el8.noarch.rpm

sudo dnf clean all

sudo dnf install -y \
  zabbix-server-pgsql \
  zabbix-web-pgsql \
  zabbix-nginx-conf \
  zabbix-sql-scripts \
  zabbix-agent2
```

Создаются роль и база `zabbix`, импортируется начальная схема, а пароль указывается в:

```text
/etc/zabbix/zabbix_server.conf
```

Запускаются службы:

```bash
sudo systemctl enable --now \
  zabbix-server \
  zabbix-agent2 \
  nginx \
  php-fpm
```

На остальных VM устанавливается `zabbix-agent2`. Основные параметры `/etc/zabbix/zabbix_agent2.conf`:

```ini
Server=192.168.77.20
ServerActive=192.168.77.20
Hostname=NODE_NAME
```

`NODE_NAME` заменяется на `ol8_pg01`, `ol8_pg02`, `ol8_pg03` или `ol8_backup01`.

На PostgreSQL-узлах дополнительно устанавливается плагин:

```bash
sudo dnf install -y zabbix-agent2-plugin-postgresql
sudo systemctl restart zabbix-agent2
```

В Zabbix создаются четыре хоста и подключаются шаблоны:

```text
Linux by Zabbix agent
PostgreSQL by Zabbix agent 2
```

Для PostgreSQL-узлов задаются macros:

```text
{$PG.URI}      = tcp://127.0.0.1:5432
{$PG.USER}     = zbx_monitor
{$PG.PASSWORD} = пароль роли
{$PG.DATABASE} = postgres
```



### Подключение Zabbix к Grafana

Устанавливается плагин:

```bash
sudo grafana cli plugins install \
  alexanderzobnin-zabbix-app

sudo systemctl restart grafana-server
```

В Grafana плагин включается, после чего добавляется источник:

```text
Type: Zabbix
URL: http://127.0.0.1:8080/api_jsonrpc.php
```

Для подключения используется отдельный пользователь Zabbix с правами только на чтение наблюдаемых хостов.

### Итого

После настройки:

* четыре Node Exporter отображаются в Prometheus как `UP`;
* три Postgres Exporter отдают метрики PostgreSQL;
* Grafana отображает Linux- и PostgreSQL-метрики из Prometheus;
* Zabbix получает данные от четырёх Agent 2;
* Zabbix контролирует PostgreSQL через официальный Agent 2 plugin;
* метрики Zabbix доступны в Grafana;
* для мониторинга БД не используются суперпользователь и открытый пароль `postgres`.


## 16. Web-версия pgAdmin в Docker с Nginx

pgAdmin разворачивается на `ol8_backup01` (`192.168.77.20`). Контейнер доступен только локально на порту `5050`, а пользователи подключаются через Nginx на порту `80`.

### Установка Docker CE

Подключается официальный репозиторий Docker:

```bash
sudo dnf install -y dnf-utils

sudo dnf config-manager \
  --add-repo \
  https://download.docker.com/linux/centos/docker-ce.repo

sudo dnf install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo systemctl enable --now docker
```

Проверка:

```bash
sudo docker version
sudo docker compose version
sudo docker run --rm hello-world
```

### Подготовка pgAdmin

Создаётся рабочий каталог:

```bash
sudo install -d -m 0700 /opt/pgadmin
```

Пароль администратора сохраняется в отдельном файле, а не в `compose.yaml`:

```bash
read -rsp "pgAdmin password: " PGADMIN_PASSWORD
printf '%s' "$PGADMIN_PASSWORD" |
  sudo tee /opt/pgadmin/pgadmin_password >/dev/null
unset PGADMIN_PASSWORD

sudo chmod 0600 /opt/pgadmin/pgadmin_password
```

Создаётся `/opt/pgadmin/compose.yaml`:

```yaml
services:
  pgadmin:
    image: dpage/pgadmin4:9.16
    container_name: pgadmin
    restart: unless-stopped

    ports:
      - "127.0.0.1:5050:80"

    environment:
      PGADMIN_DEFAULT_EMAIL: admin@example.com
      PGADMIN_DEFAULT_PASSWORD_FILE: /run/secrets/pgadmin_password
      PGADMIN_DISABLE_POSTFIX: "1"

    secrets:
      - pgadmin_password

    volumes:
      - pgadmin_data:/var/lib/pgadmin

secrets:
  pgadmin_password:
    file: ./pgadmin_password

volumes:
  pgadmin_data:
```

Используется фиксированная версия образа, а данные сохраняются в Docker volume. Это позволяет пересоздавать контейнер без потери настроек. [Документация pgAdmin](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html)

Запуск:

```bash
cd /opt/pgadmin

sudo docker compose config
sudo docker compose pull
sudo docker compose up -d
```

Проверка:

```bash
sudo docker compose ps
sudo docker compose logs --tail=50 pgadmin
curl -I http://127.0.0.1:5050
```

Порт `5050` привязан только к `127.0.0.1` и недоступен напрямую из сети.

### Настройка Nginx

Если Nginx ещё не установлен:

```bash
sudo dnf install -y nginx
sudo systemctl enable --now nginx
```

Создаётся `/etc/nginx/conf.d/pgadmin.conf`:

```nginx
server {
    listen 80;
    server_name pgadmin.devops.test 192.168.77.20;

    client_max_body_size 100m;

    location / {
        proxy_pass http://127.0.0.1:5050;
        proxy_redirect off;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 300;
    }
}
```

Для обращения Nginx к контейнеру разрешается сетевое соединение в SELinux:

```bash
sudo setsebool -P httpd_can_network_connect 1
```

Проверка и применение конфигурации:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

В firewall открывается только Nginx:

```bash
sudo firewall-cmd \
  --permanent \
  --add-service=http

sudo firewall-cmd --reload
```

### Подключение к PostgreSQL

В браузере открывается:

```text
http://192.168.77.20
```

После входа в pgAdmin регистрируется сервер:

| Параметр             | Значение                     |
| -------------------- | ---------------------------- |
| Name                 | `PostgreSQL HA`              |
| Host                 | `192.168.77.10`              |
| Port                 | `5432`                       |
| Maintenance database | `postgres`                   |
| Username             | существующая роль PostgreSQL |
| SSL mode             | `Prefer`                     |

Для административной работы используется прямой PostgreSQL-порт `5432`, а не PgBouncer `6432`. VIP автоматически направляет подключение на текущий Patroni Leader.

Проверка через Query Tool:

```sql
SELECT inet_server_addr(),
       current_database(),
       current_user,
       pg_is_in_recovery();
```

`pg_is_in_recovery()` должен возвращать `false`.

### Итого

После настройки:

* Docker CE и Compose работают на `ol8_backup01`;
* контейнер `pgadmin` автоматически запускается после перезагрузки;
* настройки pgAdmin сохраняются в постоянном Docker volume;
* порт `5050` доступен только локально;
* Nginx предоставляет pgAdmin по адресу `http://192.168.77.20`;
* pgAdmin подключается к текущему PostgreSQL Leader через VIP `192.168.77.10:5432`;
* пароль администратора pgAdmin отсутствует в `compose.yaml`.


## 17. Проверка сетевого трафика и доступности портов

Для проверки стенда используются:

* `nmap` — поиск узлов и открытых портов;
* `netcat` — проверка TCP-соединения с конкретным портом;
* `tcpdump` — просмотр фактического сетевого трафика.

Проверяются только узлы лабораторной сети `192.168.77.0/24`.

### Установка инструментов

На всех VM:

```bash
ansible all \
  -i inventory.yaml \
  --become \
  --ask-become-pass \
  -m ansible.builtin.dnf \
  -a "name=tcpdump,nmap,nmap-ncat state=present"
```

Проверка:

```bash
nmap --version
nc -h
tcpdump --version
```

### Основные порты стенда

| Адрес              | Сервисы и порты                                                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `192.168.77.10`    | PostgreSQL `5432`, PgBouncer `6432`                                                                                            |
| `192.168.77.11–13` | SSH `22`, PostgreSQL `5432`, PgBouncer `6432`, Patroni `8008`, ETCD `2379/2380`, exporters `9100/9187`, Zabbix Agent `10050`   |
| `192.168.77.20`    | SSH `22`, pgAdmin/Nginx `80`, Grafana `3000`, Zabbix Web `8080`, Prometheus `9090`, Node Exporter `9100`, Zabbix `10050/10051` |

Порт pgAdmin `5050` должен быть доступен только локально на `ol8_backup01`.

### Проверка с помощью nmap

Проверка PostgreSQL-узлов выполняется с `ol8_backup01`, поскольку firewall разрешает этому серверу доступ к exporters и Zabbix Agent. Проверка недоступности порта `5050` дополнительно выполняется с WSL или другой VM.

Поиск доступных узлов:

```bash
nmap -sn 192.168.77.0/24
```

Проверка VIP:

```bash
nmap \
  -Pn \
  -sT \
  -sV \
  -p 5432,6432 \
  192.168.77.10
```

Проверка PostgreSQL-узлов:

```bash
nmap \
  -Pn \
  -sT \
  -sV \
  -p 22,2379,2380,5432,6432,8008,9100,9187,10050 \
  192.168.77.11-13
```

Проверка сервера мониторинга и pgAdmin:

```bash
nmap \
  -Pn \
  -sT \
  -sV \
  -p 22,80,3000,5050,8080,9090,9100,10050,10051 \
  192.168.77.20
```

Ожидается, что `5050/tcp` будет закрыт извне, поскольку контейнер привязан к `127.0.0.1`.

### Проверка с помощью netcat

Проверка PostgreSQL через VIP:

```bash
nc -z -v -w 3 192.168.77.10 5432
nc -z -v -w 3 192.168.77.10 6432
```

Проверка ETCD и Patroni:

```bash
nc -z -v -w 3 192.168.77.11 2379
nc -z -v -w 3 192.168.77.12 2380
nc -z -v -w 3 192.168.77.13 8008
```

Проверка сервисов мониторинга:

```bash
nc -z -v -w 3 192.168.77.20 80
nc -z -v -w 3 192.168.77.20 3000
nc -z -v -w 3 192.168.77.20 8080
nc -z -v -w 3 192.168.77.20 9090
```

Проверка закрытого внешнего доступа к контейнеру pgAdmin:

```bash
nc -z -v -w 3 192.168.77.20 5050
```

Последняя команда должна завершиться ошибкой. `netcat` подтверждает TCP-доступность, но не проверяет работу приложения внутри порта.

### Трафик PostgreSQL

На текущем Patroni Leader запускается захват:

```bash
sudo timeout 20 tcpdump \
  -nn \
  -i any \
  'host 192.168.77.20 and (tcp port 5432 or tcp port 6432)'
```

В это время с `ol8_backup01` выполняется подключение:

```bash
psql \
  -h 192.168.77.10 \
  -p 6432 \
  -U DB_USER \
  -d demo \
  -W \
  -c "SELECT pg_is_in_recovery();"
```

`DB_USER` заменяется ролью PostgreSQL, добавленной в `/etc/pgbouncer/userlist.txt`.

В `tcpdump` должны появиться пакеты между `192.168.77.20` и текущим владельцем VIP.

### Трафик pgAdmin и Nginx

На `ol8_backup01`:

```bash
sudo timeout 20 tcpdump \
  -nn \
  -i any \
  'tcp port 80 or tcp port 5050'
```

Во время захвата в браузере открывается:

```text
http://192.168.77.20
```

Должны отображаться:

* входящее подключение клиента к Nginx на `80`;
* локальное подключение Nginx к контейнеру на `127.0.0.1:5050`.

### Трафик Prometheus

На одном из PostgreSQL-узлов:

```bash
sudo timeout 30 tcpdump \
  -nn \
  -i any \
  'host 192.168.77.20 and (tcp port 9100 or tcp port 9187)'
```

Prometheus выполняет опрос exporters каждые 15 секунд, поэтому должны появиться подключения от `192.168.77.20`.

### Трафик Keepalived

VRRP использует IP-протокол `112`, а не TCP-порт:

```bash
sudo timeout 10 tcpdump \
  -nn \
  -i any \
  'ip proto 112'
```

Должны отображаться VRRP-пакеты между PostgreSQL-узлами.

### Итого

После проверки подтверждается, что:

* четыре VM доступны в сети;
* PostgreSQL и PgBouncer доступны через VIP;
* ETCD и Patroni доступны на PostgreSQL-узлах;
* Prometheus, Grafana, Zabbix и Nginx отвечают на своих портах;
* порт контейнера pgAdmin `5050` закрыт для внешних подключений;
* `tcpdump` фиксирует трафик PostgreSQL, pgAdmin, exporters и VRRP;
* открытые порты соответствуют назначению узлов.

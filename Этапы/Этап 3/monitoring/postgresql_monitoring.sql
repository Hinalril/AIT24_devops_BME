\set ON_ERROR_STOP on

SELECT 'CREATE ROLE postgres_exporter LOGIN'
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = 'postgres_exporter'
)
\gexec

SELECT 'CREATE ROLE zbx_monitor LOGIN'
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = 'zbx_monitor'
)
\gexec

ALTER ROLE postgres_exporter LOGIN;
ALTER ROLE zbx_monitor LOGIN;

\password postgres_exporter
\password zbx_monitor

GRANT CONNECT ON DATABASE postgres TO postgres_exporter;
GRANT CONNECT ON DATABASE postgres TO zbx_monitor;
GRANT pg_monitor TO postgres_exporter;
GRANT pg_monitor TO zbx_monitor;

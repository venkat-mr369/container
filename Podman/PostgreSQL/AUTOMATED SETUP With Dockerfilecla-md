
### 🧱 AUTOMATED SETUP With Dockerfile

---

### 1. Folder structure

```
postgres-repmgr/
├── Dockerfile
├── start.sh
├── init.sql
├── postgresql.conf
├── pg_hba.conf
├── primary.conf
├── standby1.conf
├── standby2.conf
└── witness.conf
```

---

### 2. Dockerfile

```bash
FROM postgres:15

USER root

RUN apt-get update && apt-get install -y postgresql-15-repmgr

RUN mkdir -p /var/log/repmgr && chown -R postgres:postgres /var/log/repmgr

# Store configs in /tmp — start.sh copies them into $PGDATA at runtime
COPY postgresql.conf /tmp/postgresql.conf
COPY pg_hba.conf /tmp/pg_hba.conf

# Init script (runs only on primary's first boot)
COPY init.sql /docker-entrypoint-initdb.d/

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

ENV PGDATA=/var/lib/postgresql/data
ENV PATH=$PATH:/usr/lib/postgresql/15/bin

USER postgres

CMD ["/usr/local/bin/start.sh"]
```

---

### 3. start.sh

```bash
#!/bin/bash
set -e

# NODE_ROLE is passed via -e NODE_ROLE=primary or -e NODE_ROLE=standby
# when running the container (see podman run commands below)

if [ "$NODE_ROLE" = "primary" ]; then

  docker-entrypoint.sh postgres &
  PGPID=$!

  until pg_isready -q; do
    echo "Waiting for PostgreSQL..."
    sleep 2
  done

  cp /tmp/postgresql.conf "$PGDATA/postgresql.conf"
  cp /tmp/pg_hba.conf     "$PGDATA/pg_hba.conf"
  pg_ctl reload -D "$PGDATA"

else

  # Standby/Witness — data dir must be cloned first
  if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "Run 'repmgr standby clone' before starting this node."
    exit 1
  fi

  postgres -D "$PGDATA" &
  PGPID=$!

  until pg_isready -q; do
    echo "Waiting for PostgreSQL..."
    sleep 2
  done

fi

repmgrd -f /etc/repmgr.conf &

wait $PGPID
```

---

### 🔥 4. postgresql.conf

```sql
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
wal_log_hints = on

# REQUIRED for repmgrd automatic failover
shared_preload_libraries = 'repmgr'

logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_line_prefix = '%m [%p] %u@%d'
log_connections = on
log_disconnections = on
log_statement = 'none'
log_min_duration_statement = 500
```

---

### 🔥 5. pg_hba.conf

No changes needed — this was correct.

```sh
local   all         all                   trust
host    all         all   0.0.0.0/0       md5
host    replication repmgr 0.0.0.0/0      md5
```

---

### 6. init.sql


```sql
CREATE USER repmgr WITH REPLICATION LOGIN PASSWORD 'repmgr';
CREATE DATABASE repmgr OWNER repmgr;

\c repmgr

CREATE EXTENSION IF NOT EXISTS repmgr;

GRANT ALL ON SCHEMA repmgr TO repmgr;
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA repmgr TO repmgr;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA repmgr TO repmgr;

-- Grant access to tables created in future (e.g. by repmgr itself)
ALTER DEFAULT PRIVILEGES IN SCHEMA repmgr GRANT ALL ON TABLES    TO repmgr;
ALTER DEFAULT PRIVILEGES IN SCHEMA repmgr GRANT ALL ON SEQUENCES TO repmgr;
```

---

### 🔥 7. primary.conf

```sh
node_id=1
node_name='rep-primary'
conninfo='host=rep-primary user=repmgr password=repmgr dbname=repmgr'
data_directory='/var/lib/postgresql/data'

failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf'
follow_command='repmgr standby follow -f /etc/repmgr.conf'

log_file='/var/log/repmgr/repmgr.log'
log_level=INFO
pg_bindir='/usr/lib/postgresql/15/bin'
priority=100
```

---

### 🔥 8. standby1.conf

```sh
node_id=2
node_name='rep-standby1'
conninfo='host=rep-standby1 user=repmgr password=repmgr dbname=repmgr'
data_directory='/var/lib/postgresql/data'

failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf'
follow_command='repmgr standby follow -f /etc/repmgr.conf'

log_file='/var/log/repmgr/repmgr.log'
log_level=INFO
pg_bindir='/usr/lib/postgresql/15/bin'
priority=90   # was 100 — changed to establish clear promotion order
```

---

### standby2.conf

```sh
node_id=3
node_name='rep-standby2'
conninfo='host=rep-standby2 user=repmgr password=repmgr dbname=repmgr'
data_directory='/var/lib/postgresql/data'

failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf'
follow_command='repmgr standby follow -f /etc/repmgr.conf'

log_file='/var/log/repmgr/repmgr.log'
log_level=INFO
pg_bindir='/usr/lib/postgresql/15/bin'
priority=80
```

---

### 🔥 10. witness.conf

```ini
node_id=4
node_name='rep-witness'
conninfo='host=rep-witness user=repmgr password=repmgr dbname=repmgr'
data_directory='/var/lib/postgresql/data'

failover=automatic

log_file='/var/log/repmgr/repmgr.log'
log_level=INFO
pg_bindir='/usr/lib/postgresql/15/bin'
priority=0
```

---

### 11. Build image

```bash
podman build -t postgres-repmgr .
```

---

### 🔥 12. Run ALL nodes

#### Primary
```powershell
podman run -d --name rep-primary `
  --network pg-rep-net `
  -e POSTGRES_PASSWORD=postgres `
  -v rep-primary-data:/var/lib/postgresql/data `
  -v ${PWD}/primary.conf:/etc/repmgr.conf `
  postgres-repmgr
```

#### Standby1
```powershell
podman run -d --name rep-standby1 `
  --network pg-rep-net `
  -e POSTGRES_PASSWORD=postgres `
  -v rep-standby1-data:/var/lib/postgresql/data `
  -v ${PWD}/standby1.conf:/etc/repmgr.conf `
  postgres-repmgr
```

#### Standby2
```powershell
podman run -d --name rep-standby2 `
  --network pg-rep-net `
  -e POSTGRES_PASSWORD=postgres `
  -v rep-standby2-data:/var/lib/postgresql/data `
  -v ${PWD}/standby2.conf:/etc/repmgr.conf `
  postgres-repmgr
```

#### Witness
```powershell
podman run -d --name rep-witness `
  --network pg-rep-net `
  -e POSTGRES_PASSWORD=postgres `
  -v rep-witness-data:/var/lib/postgresql/data `
  -v ${PWD}/witness.conf:/etc/repmgr.conf `
  postgres-repmgr
```

---

```bash
# Step 1 — on rep-primary
podman exec -it rep-primary \
  repmgr -f /etc/repmgr.conf primary register

# Step 2 — on rep-standby1 (clone THEN register)
podman exec -it rep-standby1 \
  repmgr -h rep-primary -U repmgr -d repmgr -f /etc/repmgr.conf standby clone --force

podman exec -it rep-standby1 \
  repmgr -f /etc/repmgr.conf standby register

# Step 3 — on rep-standby2
podman exec -it rep-standby2 \
  repmgr -h rep-primary -U repmgr -d repmgr -f /etc/repmgr.conf standby clone --force

podman exec -it rep-standby2 \
  repmgr -f /etc/repmgr.conf standby register

# Step 4 — on rep-witness
podman exec -it rep-witness \
  repmgr -h rep-primary -U repmgr -d repmgr -f /etc/repmgr.conf witness register

# Verify cluster
podman exec -it rep-primary \
  repmgr -f /etc/repmgr.conf cluster show
```

---

### 🔥 What is automated vs manual

| Task | Status |
|------|--------|
| PostgreSQL config  | ✅ auto |
| pg_hba setup       | ✅ auto |
| User + DB creation | ✅ auto |
| Extension + grants | ✅ auto |
| repmgrd start      | ✅ auto |
| Cluster registration | ⚠️ one-time manual |

After `podman stop / start` → cluster auto-recovers, no reconfiguration needed.

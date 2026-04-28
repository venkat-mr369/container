Here's the complete fresh setup, designed so registration/clone happens **only via `podman exec`** — never inside the container's start script. That's what makes failures recoverable instead of fatal.

---

## 0. Cleanup (run first)

```powershell
podman stop rep-primary rep-standby1 rep-standby2 rep-witness 2>$null
podman rm -f rep-primary rep-standby1 rep-standby2 rep-witness 2>$null
podman volume rm rep-primary-data rep-standby1-data rep-standby2-data rep-witness-data 2>$null
podman network rm pg-rep-net 2>$null
```

---

## 1. Folder layout

```
postgres-repmgr/
├── Dockerfile
├── start.sh
├── init.sql
├── postgresql.conf
├── pg_hba.conf
├── repmgr-primary.conf
├── repmgr-standby1.conf
├── repmgr-standby2.conf
└── repmgr-witness.conf
```

---

## 2. `Dockerfile`

```dockerfile
FROM postgres:15

USER root

RUN apt-get update \
 && apt-get install -y postgresql-15-repmgr \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/repmgr /etc/postgresql \
 && chown -R postgres:postgres /var/log/repmgr /etc/postgresql

# Bake configs into image (not data dir) — picked up via -c flags at startup
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf     /etc/postgresql/pg_hba.conf

# Runs only on primary/witness first boot (empty data dir)
COPY init.sql /docker-entrypoint-initdb.d/

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh \
 && chown postgres:postgres /etc/postgresql/postgresql.conf /etc/postgresql/pg_hba.conf

ENV PGDATA=/var/lib/postgresql/data
ENV PATH=$PATH:/usr/lib/postgresql/15/bin

USER postgres
CMD ["/usr/local/bin/start.sh"]
```

---

## 3. `start.sh`

The whole point: this script **only starts Postgres**. No clone, no register. If the data dir is empty and the role is `standby`, the container just sleeps so you can clone into it from outside.

```bash
#!/bin/bash
set -e

PG_OPTS="-c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf"

case "$NODE_ROLE" in
  primary|witness)
    # docker-entrypoint.sh handles initdb + init.sql on first boot
    exec docker-entrypoint.sh postgres $PG_OPTS
    ;;

  standby)
    if [ ! -s "$PGDATA/PG_VERSION" ]; then
      echo "============================================================"
      echo " Empty data dir on $HOSTNAME (NODE_ROLE=standby)"
      echo " Container will sleep. From the host, run:"
      echo "   podman exec $HOSTNAME repmgr -h rep-primary -U repmgr \\"
      echo "     -d repmgr -f /etc/repmgr.conf standby clone --force"
      echo "   podman restart $HOSTNAME"
      echo "============================================================"
      exec sleep infinity
    fi
    exec postgres -D "$PGDATA" $PG_OPTS
    ;;

  *)
    echo "ERROR: NODE_ROLE must be primary, standby, or witness"
    exit 1
    ;;
esac
```

---

## 4. `postgresql.conf`

```conf
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
wal_log_hints = on
shared_preload_libraries = 'repmgr'

logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_line_prefix = '%m [%p] %u@%d '
log_connections = on
log_disconnections = on
log_min_duration_statement = 500
```

---

## 5. `pg_hba.conf`

```conf
local   all          all                       trust
host    all          all         0.0.0.0/0     md5
host    replication  repmgr      0.0.0.0/0     md5
host    repmgr       repmgr      0.0.0.0/0     md5
```

---

## 6. `init.sql`

```sql
CREATE USER repmgr WITH SUPERUSER REPLICATION LOGIN PASSWORD 'repmgr';
CREATE DATABASE repmgr OWNER repmgr;

\c repmgr

CREATE EXTENSION IF NOT EXISTS repmgr;
```

Note: `SUPERUSER` is the simplest path. If you want to lock it down later, you can downgrade and add per-grant statements, but for learning, superuser saves a lot of permission grief.

---

## 7. The four `repmgr-*.conf` files

**`repmgr-primary.conf`**
```ini
node_id=1
node_name='rep-primary'
conninfo='host=rep-primary user=repmgr password=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/postgresql/data'
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'
log_file='/var/log/repmgr/repmgr.log'
log_level=INFO
pg_bindir='/usr/lib/postgresql/15/bin'
priority=100
```

**`repmgr-standby1.conf`** — same as above but:
```ini
node_id=2
node_name='rep-standby1'
conninfo='host=rep-standby1 user=repmgr password=repmgr dbname=repmgr connect_timeout=2'
priority=90
```
(keep the rest identical)

**`repmgr-standby2.conf`**
```ini
node_id=3
node_name='rep-standby2'
conninfo='host=rep-standby2 user=repmgr password=repmgr dbname=repmgr connect_timeout=2'
priority=80
```

**`repmgr-witness.conf`**
```ini
node_id=4
node_name='rep-witness'
conninfo='host=rep-witness user=repmgr password=repmgr dbname=repmgr connect_timeout=2'
priority=0
```
(keep all the other lines)

---

## 8. Build the image

```powershell
podman build -t postgres-repmgr .
```

---

## 9. Create network

```powershell
podman network create pg-rep-net
```

---

## 10. Bring-up sequence (this is the actual workflow)

### Step A — Start primary

```powershell
podman run -d --name rep-primary `
  --network pg-rep-net `
  -e POSTGRES_PASSWORD=postgres `
  -e NODE_ROLE=primary `
  -v rep-primary-data:/var/lib/postgresql/data `
  -v ${PWD}/repmgr-primary.conf:/etc/repmgr.conf `
  postgres-repmgr

# Wait ~10s for initdb + init.sql
Start-Sleep -Seconds 12
podman exec rep-primary pg_isready -U postgres
```

### Step B — Register primary

```powershell
podman exec rep-primary repmgr -f /etc/repmgr.conf primary register
```

Expected: `NOTICE: primary node record (ID: 1) registered`

### Step C — Start standby1 (will sleep since data dir is empty)

```powershell
podman run -d --name rep-standby1 `
  --network pg-rep-net `
  -e NODE_ROLE=standby `
  -v rep-standby1-data:/var/lib/postgresql/data `
  -v ${PWD}/repmgr-standby1.conf:/etc/repmgr.conf `
  postgres-repmgr
```

`podman logs rep-standby1` will show the sleep message.

### Step D — Clone, restart, register standby1

```powershell
# Clone primary's data into standby1's volume
podman exec rep-standby1 `
  repmgr -h rep-primary -U repmgr -d repmgr `
  -f /etc/repmgr.conf standby clone --force

# Restart so postgres now starts on the cloned data dir
podman restart rep-standby1
Start-Sleep -Seconds 5

# Register
podman exec rep-standby1 repmgr -f /etc/repmgr.conf standby register
```

### Step E — Repeat for standby2

```powershell
podman run -d --name rep-standby2 `
  --network pg-rep-net `
  -e NODE_ROLE=standby `
  -v rep-standby2-data:/var/lib/postgresql/data `
  -v ${PWD}/repmgr-standby2.conf:/etc/repmgr.conf `
  postgres-repmgr

podman exec rep-standby2 `
  repmgr -h rep-primary -U repmgr -d repmgr `
  -f /etc/repmgr.conf standby clone --force

podman restart rep-standby2
Start-Sleep -Seconds 5

podman exec rep-standby2 repmgr -f /etc/repmgr.conf standby register
```

### Step F — Witness

Witness is a separate fresh Postgres instance — it does NOT clone from primary.

```powershell
podman run -d --name rep-witness `
  --network pg-rep-net `
  -e POSTGRES_PASSWORD=postgres `
  -e NODE_ROLE=witness `
  -v rep-witness-data:/var/lib/postgresql/data `
  -v ${PWD}/repmgr-witness.conf:/etc/repmgr.conf `
  postgres-repmgr

Start-Sleep -Seconds 12

podman exec rep-witness `
  repmgr -h rep-primary -U repmgr -d repmgr `
  -f /etc/repmgr.conf witness register
```

### Step G — Start repmgrd on each node (for automatic failover)

```powershell
podman exec -d rep-primary  repmgrd -f /etc/repmgr.conf
podman exec -d rep-standby1 repmgrd -f /etc/repmgr.conf
podman exec -d rep-standby2 repmgrd -f /etc/repmgr.conf
podman exec -d rep-witness  repmgrd -f /etc/repmgr.conf
```

### Step H — Verify

```powershell
podman exec rep-primary repmgr -f /etc/repmgr.conf cluster show
podman exec rep-primary psql -U postgres -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"
```

You should see all 4 nodes in `cluster show`, and 2 streaming standbys in `pg_stat_replication`.

---

## Mental model

| What | Where |
|------|-------|
| Postgres lifecycle | `start.sh` (just starts the DB, nothing else) |
| Configs | Baked into `/etc/postgresql/` in the image, applied via `-c` flags |
| `init.sql` | Runs once on first boot of primary/witness via docker-entrypoint |
| Clone, register, repmgrd start | **All via `podman exec` — never in start.sh** |
| Empty standby on first boot | Sleeps until you clone into it externally |

After this is set up, `podman stop` / `podman start` of any node does not require re-cloning or re-registering — the data and metadata persist in the volume.

Want me to also add a quick failover test (kill primary, watch standby1 promote) once you've got this running cleanly?

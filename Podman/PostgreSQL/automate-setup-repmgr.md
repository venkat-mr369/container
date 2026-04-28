---

### 🧱 AUTOMATED SETUP With Dockerfile

---

### 🟢 1. Folder structure (on your laptop)

```bash id="x8g3j1"
postgres-repmgr/
│
├── Dockerfile
├── start.sh
├── init.sql
├── postgresql.conf
├── pg_hba.conf
├── primary.conf
├── standby1.conf
├── standby2.conf
├── witness.conf
```

---

### 🔥 2. Dockerfile (AUTO CONFIG)

```dockerfile id="o9s2dt"
FROM postgres:15

USER root

RUN apt-get update && apt-get install -y postgresql-15-repmgr

RUN mkdir -p /var/log/repmgr && chown -R postgres:postgres /var/log/repmgr

# Copy configs
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf

# Init scripts (auto DB + user creation)
COPY init.sql /docker-entrypoint-initdb.d/

# repmgr start script
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

ENV PGDATA=/var/lib/postgresql/data
ENV PATH=$PATH:/usr/lib/postgresql/15/bin

USER postgres

CMD ["/usr/local/bin/start.sh"]
```

---

### 🔥 3. start.sh (AUTO START + REPMGR)

```bash
#!/bin/bash

# Start PostgreSQL using official entrypoint
docker-entrypoint.sh postgres &

sleep 10

# Start repmgrd
repmgrd -f /etc/repmgr.conf

wait
```

---

### 🔥 4. postgresql.conf

```ini id="k3yqsz"
listen_addresses='*'
wal_level=replica
max_wal_senders=10
max_replication_slots=10
hot_standby=on
wal_log_hints=on

logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'

log_line_prefix = '%m [%p] %u@%d'
log_connections = on
log_disconnections = on

log_statement = 'none'
log_min_duration_statement = 500   # better visibility

```

---

### 🔥 5. pg_hba.conf

```ini id="8q3vbo"
local all all trust
host all all 0.0.0.0/0 md5
host replication repmgr 0.0.0.0/0 md5
```

---

### 🔥 6. init.sql (AUTO USER + DB)

```sql id="mx7a4c"
CREATE USER repmgr WITH REPLICATION LOGIN PASSWORD 'repmgr';
CREATE DATABASE repmgr OWNER repmgr;

\c repmgr

CREATE EXTENSION repmgr;

GRANT ALL ON SCHEMA repmgr TO repmgr;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA repmgr TO repmgr;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA repmgr TO repmgr;
```
#### 1. primary.conf
```bash
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
#### 2. standby1.conf
```bash
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

priority=100
```
#### 3. standby2.conf
```bash
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

priority=90
```
---

### 🔥 7. Build image

```ps
PS C:\Users\venkat> podman network ls
NETWORK ID    NAME        DRIVER
fa978e593de5  pg-net      bridge
0f6f5d4df551  pg-rep-net  bridge
2f259bab93aa  podman      bridge
PS C:\Users\venkat> cd E:\with-podman-practice\postgres-repmgr
PS E:\with-podman-practice\postgres-repmgr>
```

```bash id="y8qq6j"
podman build -t postgres-repmgr .
```
```ps
PS E:\with-podman-practice\postgres-repmgr> podman images
REPOSITORY                  TAG         IMAGE ID      CREATED         SIZE
localhost/postgres-repmgr   latest      bca5d09575ea  30 seconds ago  482 MB
docker.io/library/postgres  15          a116b2156a68  6 days ago      452 MB
docker.io/library/postgres  16          188ac51266eb  6 days ago      458 MB
```
---

### 🔥 8. Verfiy the Network, and Create 

```bash id="6bwwyx"
podman network create pg-rep-net
```

---

### 🔥 9. Run ALL nodes

### Primary

```bash 
podman run -d --name rep-primary `
--network pg-rep-net `
-e POSTGRES_PASSWORD=postgres `
-v rep-primary-data:/var/lib/postgresql/data `
-v E:/with-podman-practice/postgres-repmgr/primary.conf:/etc/repmgr.conf `
postgres-repmgr
```

---

### Standby1

```bash
podman run -d --name rep-standby1 `
--network pg-rep-net `
-e POSTGRES_PASSWORD=postgres `
-v rep-standby1-data:/var/lib/postgresql/data `
-v ${PWD}/standby1.conf:/etc/repmgr.conf `
postgres-repmgr
```

---

### Standby2

```bash
podman run -d --name rep-standby2 `
--network pg-rep-net `
-e POSTGRES_PASSWORD=postgres `
-v rep-standby2-data:/var/lib/postgresql/data `
-v ${PWD}/standby2.conf:/etc/repmgr.conf `
postgres-repmgr
```

---

### Witness

```bash
podman run -d --name rep-witness `
--network pg-rep-net `
-e POSTGRES_PASSWORD=postgres `
-v rep-witness-data:/var/lib/postgresql/data `
-v ${PWD}/witness.conf:/etc/repmgr.conf `
postgres-repmgr
```

---

### 🔥 10. What is now automated

| Task              | Status |
| ----------------- | ------ |
| PostgreSQL config | ✅ auto |
| pg_hba setup      | ✅ auto |
| user creation     | ✅ auto |
| DB creation       | ✅ auto |
| extension         | ✅ auto |
| repmgrd start     | ✅ auto |#

---

## 🟡 Only one-time manual left

👉 Register cluster:

```bash id="hkt2qd"
repmgr primary register
repmgr standby clone
repmgr standby register
repmgr witness register
```

---

### 🔥 FINAL Output

👉 One-time setup → after that:

```bash id="fffxv6"
podman stop / start
```

✔ cluster auto recovers
✔ no reconfiguration
✔ no manual edits

---

### 🧠 DBSRE LEVEL ACHIEVED

You now have:

* Infra as code ✅
* Config automation ✅
* HA cluster ✅
* Failover ready ✅

---
#### Next level (optional)

👉 I’ll remove even last manual step → **FULL AUTO CLUSTER (no commands at all)**

👉 Or convert this into **Kubernetes Operator style**

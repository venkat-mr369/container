### repmgr-based PostgreSQL HA Lab (Podman)

---

### 🔹 1. Container Naming

```
rep-primary
rep-standby1
rep-standby2
rep-witness
pgpool (later)
```

---

### 🔹 2. Network

```bash
podman network create pg-rep-net
```

---

### 🔹 3. Volumes

```bash
podman volume create rep-primary-data
podman volume create rep-standby1-data
podman volume create rep-standby2-data
podman volume create rep-witness-data
```

---

### 🔹 4. Start Primary

```bash
podman run -d --name rep-primary \
  --network pg-rep-net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -v rep-primary-data:/var/lib/postgresql/data \
  docker.io/postgres:15
```

---

### PRIMARY CONFIGURATION

### 🔹 5. Enter Container

```bash
podman exec -it rep-primary bash
```

---

### 🔹 6. Install repmgr (IMPORTANT FIX)

👉 run as **root**

```bash
apt update
apt install -y postgresql-15-repmgr
```

---

### 🔹 7. Switch to postgres user

```bash
su - postgres
```

---

### 🔹 8. Create User & DB

```bash
psql
```

```sql
CREATE USER repmgr WITH REPLICATION LOGIN PASSWORD 'repmgr';
CREATE DATABASE repmgr OWNER repmgr;
\c repmgr
CREATE EXTENSION repmgr;
\q
```

---

### 🔹 9. Fix Permissions (VERY IMPORTANT)

```bash
psql -d repmgr

```

```sql
GRANT ALL ON SCHEMA repmgr TO repmgr;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA repmgr TO repmgr;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA repmgr TO repmgr;
\q
```

---

### 🔹 10. Configure PostgreSQL

Edit:

```bash
vi /var/lib/postgresql/data/postgresql.conf
```

Add/Uncomment:

```
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
listen_addresses='*'
```

---

### 🔹 11. Configure pg_hba.conf

```bash
vi /var/lib/postgresql/data/pg_hba.conf
```

Add:

```
host replication repmgr 0.0.0.0/0 md5
host repmgr repmgr 0.0.0.0/0 md5
```

Reload:

```bash
--try any method 
pg_ctl reload
psql -U postgres -c "SELECT pg_reload_conf();"
pg_ctl -D /var/lib/postgresql/data reload

```

---

### 🔹 12. Create repmgr.conf

```bash
vi /etc/repmgr.conf
```

```
node_id=1
node_name=rep-primary
conninfo='host=rep-primary user=repmgr password=repmgr dbname=repmgr'
data_directory='/var/lib/postgresql/data'
```

---

### 🔹 13. Register Primary

```bash
repmgr primary register
```

---

### STANDBY SETUP (rep-standby1)

### 🔹 14. Start Container

```bash
podman run -it --name rep-standby1 --network pg-rep-net -e POSTGRES_PASSWORD=postgres -v rep-standby1-data:/var/lib/postgresql/data --entrypoint bash docker.io/postgres:15
```

---

### 🔹 15. Enter & Install

```bash
podman exec -it rep-standby1 bash
apt update
apt install -y postgresql-15-repmgr
apt install nano -y
```

---

### 🔹 16. Switch user

```bash
su - postgres
```

---

### 🔹 17. Stop PostgreSQL

```bash
/usr/lib/postgresql/15/bin/pg_ctl -D /var/lib/postgresql/data stop
pg_ctl -D /var/lib/postgresql/data stop
```

---

### 🔹 18. Create repmgr.conf (from root user)

```bash
---Execute from root user
vi /etc/repmgr.conf
```

```
node_id=2
node_name=rep-standby1
conninfo='host=rep-standby1 user=repmgr password=repmgr dbname=repmgr'
data_directory='/var/lib/postgresql/data'
----
chown postgres:postgres /etc/repmgr.conf
chmod 600 /etc/repmgr.conf
```

---

### 🔹 19. Clone from Primary

```bash
su - postgres
rm -rf /var/lib/postgresql/data/*
export PGPASSWORD=repmgr
repmgr -h rep-primary -U repmgr -d repmgr -D /var/lib/postgresql/data standby clone

```

---

### 🔹 20. Start DB

```bash
/usr/lib/postgresql/15/bin/pg_ctl -D /var/lib/postgresql/data start
```

---

### 🔹 21. Register

```bash
repmgr standby register
```
```bash
repmgr cluster show
```
--- to verify
```sql
postgres=# select pg_is_in_recovery();
 pg_is_in_recovery
-------------------
 t
(1 row)
```
```sql
---verify from primary node 
postgres@b1ebe35834ac:~/data$ psql -U postgres -c "select client_addr, state from pg_stat_replication;"
 client_addr |   state
-------------+-----------
 10.89.1.15  | streaming
(1 row)
```
---

### 🔁 Repeat for standby2

```bash
podman rm -f rep-standby2
podman volume rm rep-standby2-data
podman volume create rep-standby2-data
```
```bash
podman run -it --name rep-standby2 --network pg-rep-net -e POSTGRES_PASSWORD=postgres -v rep-standby2-data:/var/lib/postgresql/data --entrypoint bash docker.io/postgres:15
```
```
apt update && apt install -y postgresql-15-repmgr && apt install -y nano
```
```bash
rm -rf /var/lib/postgresql/data/*
```
Create config (as root)
```bash
vi /etc/repmgr.conf
```
Add:
```bash
node_id=3
node_name=rep-standby2
conninfo='host=rep-standby2 user=repmgr password=repmgr dbname=repmgr'
data_directory='/var/lib/postgresql/data'
```
Provide permissions:
```bash
chown postgres:postgres /etc/repmgr.conf
chmod 600 /etc/repmgr.conf
```
```bash
su - postgres
export PGPASSWORD=repmgr
repmgr -h rep-primary -U repmgr -d repmgr -D /var/lib/postgresql/data standby clone
```
Wait until:
```
standby clone successful
---
```bash
/usr/lib/postgresql/15/bin/pg_ctl -D /var/lib/postgresql/data start
```
Register
```bash
repmgr standby register
```
#### ✅ Final Verification
```bash
repmgr cluster show
```
---Success output
```bash
postgres@2846caa3bbcc:/$ repmgr cluster show
 ID | Name         | Role    | Status    | Upstream    | Location | Priority | Timeline | Connection string
----+--------------+---------+-----------+-------------+----------+----------+----------+-------------------------------------------------------------
 1  | rep-primary  | primary | * running |             | default  | 100      | 1        | host=rep-primary user=repmgr dbname=repmgr password=repmgr
 2  | rep-standby1 | standby |   running | rep-primary | default  | 100      | 1        | host=rep-standby1 user=repmgr password=repmgr dbname=repmgr
 3  | rep-standby2 | standby |   running | rep-primary | default  | 100      | 1        | host=rep-standby2 user=repmgr password=repmgr dbname=repmgr
postgres@2846caa3bbcc:/$
```
From Primary Node, verify this 
```sql
postgres@b1ebe35834ac:~/data$ hostname -a
rep-primary
postgres@b1ebe35834ac:~/data$ psql -U postgres -c "select client_addr, state from pg_stat_replication;"
 client_addr |   state
-------------+-----------
 10.89.1.15  | streaming
 10.89.1.16  | streaming
(2 rows)
```

### 🟡 WITNESS NODE SETUP

### 🔹 22. Start Witness

---suppose if you face issues, clean it & recreate
```bash
podman rm -f rep-witness
podman volume rm rep-witness-data
podman volume create rep-witness-data
```
```bash
podman run -d --name rep-witness --network pg-rep-net -e POSTGRES_PASSWORD=postgres -v rep-witness-data:/var/lib/postgresql/data docker.io/postgres:15
```

---

### 🔹 23. Install & Configure

Same steps as standby but:

```
podman exec -it rep-witness bash
apt update && apt install -y postgresql-15-repmgr && apt install -y nano
```
---Switch to postgres user
```
su - postgres
psql -U postgres
CREATE DATABASE repmgr OWNER repmgr;
\c repmgr
CREATE EXTENSION repmgr;
\q
node_id=4
node_name=rep-witness
```

---

## 🔹 24. Register Witness

```bash
repmgr witness register -h rep-primary -U repmgr -d repmgr
```

---

# 🔹 25. Verify Cluster

From primary:

```bash
repmgr cluster show
```

---

# 🧠 What is Witness? (IMPORTANT)

Without witness:

👉 Network split ayite:

* standby thinks primary is dead
* becomes new primary ❌
* **split-brain problem**

With witness:

👉 witness acts like **tie-breaker**

* decides who is real primary
* avoids dual primary

---

# 🔥 Final Architecture

```
        rep-primary
        /        \
rep-standby1   rep-standby2
        \
        rep-witness
```

---

# 🚀 Next Steps

Once this is done:

👉 setup `repmgrd` (auto failover)
👉 simulate failover (kill primary 🔥)
👉 add Pgpool-II
👉 add Grafana

---

If you want next, I’ll give you:

👉 **auto failover full setup + interview explanation (very important)**

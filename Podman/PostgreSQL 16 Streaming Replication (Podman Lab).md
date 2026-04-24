--

# 🐘 PostgreSQL 16 Streaming Replication (Podman Lab)

## 🧱 Architecture

* Container 1 → `pg-primary`
* Container 2 → `pg-standby`
* Network → `pg-net`
* Volumes → persistent data

---

# ⚙️ Step 1: Create Network

```bash
podman network create pg-net
```

---

# 📦 Step 2: Create Volumes

```bash
podman volume create pg-primary-data
podman volume create pg-standby-data
```

---

# 🚀 Step 3: Start Primary Container

```bash
podman run -d `
  --name pg-primary `
  --network pg-net `
  -e POSTGRES_PASSWORD=postgres `
  -v pg-primary-data:/var/lib/postgresql/data `
  postgres:16
```

👉 Check:

```bash
podman ps
```

---

# 🔧 Step 4: Configure Primary

### 🔹 Enter container

```bash
podman exec -it pg-primary bash
```

---

### 🔹 Edit postgresql.conf

```bash
vi /var/lib/postgresql/data/postgresql.conf
```

Add/modify:

```conf
listen_addresses='*'
wal_level=replica
max_wal_senders=10
wal_keep_size=512MB
```

---

### 🔹 Edit pg_hba.conf

```bash
vi /var/lib/postgresql/data/pg_hba.conf
```

Add this line at bottom:

```conf
host replication replicator 0.0.0.0/0 md5
```

---

### 🔹 Create replication user

```bash
psql -U postgres
```

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replica123';
```

Exit:

```bash
\q
exit
```

---

### 🔹 Restart Primary

```bash
podman restart pg-primary
```

---

# 📥 Step 5: Take Base Backup (Standby Setup)

👉 Run temporary container:

```bash
podman run -it --rm `
  --name pg-standby-init `
  --network pg-net `
  -e PGPASSWORD=replica123 `
  -v pg-standby-data:/var/lib/postgresql/data `
  postgres:16 bash
```

---

### 🔹 Inside container run:

```bash
pg_basebackup -h pg-primary -D /var/lib/postgresql/data `
  -U replicator -Fp -Xs -P -R
```

👉 This is very important:

* Copies primary data
* Creates `standby.signal`
* Adds connection config

Exit:

```bash
exit
```

---

# 🚀 Step 6: Start Standby Container

```bash
podman run -d `
  --name pg-standby `
  --network pg-net `
  -v pg-standby-data:/var/lib/postgresql/data `
  postgres:16
```

---

# ✅ Step 7: Verification

## 🔹 Check on Primary

```bash
podman exec -it pg-primary psql -U postgres
```

```sql
SELECT client_addr, state, sync_state FROM pg_stat_replication;
```

👉 Expect:

* standby connected
* state = streaming

---

## 🔹 Check on Standby

```bash
podman exec -it pg-standby psql -U postgres
```

```sql
SELECT pg_is_in_recovery();
```

👉 Output:

```text
true
```

---

# 🧪 Step 8: Real Test

## On Primary

```sql
CREATE TABLE test_rep(id INT);
INSERT INTO test_rep VALUES (1),(2),(3);
```

---

## On Standby

```sql
SELECT * FROM test_rep;
```

👉 You should see data ✅

---

# 🔥 Deep Understanding (Important)

## What actually happens:

1. Primary writes WAL
2. WAL sender sends logs
3. Standby WAL receiver gets logs
4. Applies continuously

---

# ⚠️ Common Errors (You WILL face)

### ❌ Connection refused

* Check network (`pg-net`)
* Check container name

---

### ❌ Authentication failed

* pg_hba.conf issue
* Wrong password

---

### ❌ No replication

* wal_level not set
* restart missed

---

### ❌ Standby not starting

* Data directory not empty
* base backup failed

---

# 🚀 Next Level Practice (Do after this)

Once this works, I recommend:

👉 Add:

* Replication slots
* Synchronous replication
* Failover (manual promotion)
* 3-node setup

---

If you want next:

👉 I can give:

* **Failover testing (promote standby)**
* **Patroni cluster (production level 🔥)**
* **Postgres tuning + monitoring (Grafana)**


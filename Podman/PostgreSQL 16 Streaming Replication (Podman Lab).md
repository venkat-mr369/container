### 🐘 PostgreSQL 16 Streaming Replication (Podman Lab)

### 🧱 Architecture

* Primary: pg-primary
* Standby: pg-standby
* Network: pg-net
* Volumes: persistent storage

---

### ⚙️ Step 1: Create Network

```bash
podman network create pg-net
```

---

### 📦 Step 2: Create Volumes

```bash
podman volume create pg-primary-data
podman volume create pg-standby-data
```

---

### 🚀 Step 3: Start Primary Container (SAFE COMMAND)

```bash
podman run -d --name pg-primary --network pg-net -e POSTGRES_PASSWORD=postgres -v pg-primary-data:/var/lib/postgresql/data postgres:16
```

Verify:

```bash
podman ps
```

---

### 🔧 Step 4: Configure Primary

Enter container:

```bash
podman exec -it pg-primary bash
```

---

Edit postgresql.conf:

```bash
nano /var/lib/postgresql/data/postgresql.conf
```

Update:

```conf
listen_addresses='*'
wal_level=replica
max_wal_senders=10
wal_keep_size=512MB
```

---

Edit pg_hba.conf:

```bash
nano /var/lib/postgresql/data/pg_hba.conf
```

ADD THIS LINE (IMPORTANT - CORRECT FORMAT):

```conf
host replication replicator 10.89.0.0/24 md5
```

Save:

Ctrl + O → Enter → Ctrl + X

---

Create replication user:

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

Restart primary:

```bash
podman restart pg-primary
```

---

### 📥 Step 5: Standby Initialization (Base Backup)

Remove old init container if exists:

```bash
podman rm -f pg-standby-init
```

Run init container:

```bash
podman run -it --rm --name pg-standby-init --network pg-net -e PGPASSWORD=replica123 -v pg-standby-data:/var/lib/postgresql/data postgres:16 bash
```

---

Inside container (VERY IMPORTANT STEPS):

Clean directory (fix "not empty" error):

```bash
rm -rf /var/lib/postgresql/data/*
```

Run base backup:

```bash
pg_basebackup -h pg-primary -D /var/lib/postgresql/data -U replicator -Fp -Xs -P -R
```

Expected:

```text
progress: 100%
```

Exit:

```bash
exit
```

---

### 🚀 Step 6: Start Standby Container

```bash
podman run -d --name pg-standby --network pg-net -v pg-standby-data:/var/lib/postgresql/data postgres:16
```

---

### ✅ Step 7: Verification

On Primary:

```bash
podman exec -it pg-primary psql -U postgres
```

```sql
SELECT client_addr, state FROM pg_stat_replication;
```

Expected:

* state = streaming

---

On Standby:

```bash
podman exec -it pg-standby psql -U postgres
```

```sql
SELECT pg_is_in_recovery();
```

Expected:

```text
true
```

---

### 🧪 Step 8: Test Replication

On Primary:

```sql
CREATE TABLE test_rep(id INT);
INSERT INTO test_rep VALUES (1),(2),(3);
```

On Standby:

```sql
SELECT * FROM test_rep;
```

You should see data.

---

### 🔥 Key Understanding

* Primary generates WAL
* WAL sender sends data
* Standby receives WAL
* Standby applies changes continuously

---

### ⚠️ Common Errors & Fixes

Authentication failed:

* Fix password using ALTER ROLE

pg_hba.conf error:

* Use: host replication replicator <subnet> md5

Directory not empty:

* Run: rm -rf data/*

Connection refused:

* Check network and container name

---

### 🚀 Next Practice

* Manual failover (pg_ctl promote)
* Replication slots
* Synchronous replication
* 3-node setup

---

This version avoids PowerShell issues, fixes pg_hba mistakes, and handles real errors you faced.

### 🐘 PostgreSQL Logical Replication (Podman Lab)

### 🧱 Architecture

* Publisher (Primary DB) → pg-publisher
* Subscriber (Replica DB) → pg-subscriber
* Network → pg-net
* Replication Type → Logical (table-level)

---

### ⚙️ Step 1: Create Network

```bash
podman network create pg-net
```

---

### 📦 Step 2: Create Volumes

```bash
podman volume create pub-data
podman volume create sub-data
```

---

### 🚀 Step 3: Start Publisher

```bash
podman run -d --name pg-publisher --network pg-net -e POSTGRES_PASSWORD=postgres -v pub-data:/var/lib/postgresql/data postgres:16
```

---

### 🚀 Step 4: Start Subscriber

```bash
podman run -d --name pg-subscriber --network pg-net -e POSTGRES_PASSWORD=postgres -v sub-data:/var/lib/postgresql/data postgres:16
```

---

### 🔧 Step 5: Configure Publisher

Enter container:

```bash
podman exec -it pg-publisher bash
```

Edit config:

```bash
nano /var/lib/postgresql/data/postgresql.conf
```

Add:

```conf
wal_level=logical
max_replication_slots=10
max_wal_senders=10
```

---

Edit pg_hba.conf:

```bash
nano /var/lib/postgresql/data/pg_hba.conf
```

Add:

```conf
host all all 0.0.0.0/0 md5
```

---

Restart publisher:

```bash
exit
podman restart pg-publisher
```

---

### 🧪 Step 6: Create Test Table (Publisher)

```bash
podman exec -it pg-publisher psql -U postgres
```

```sql
CREATE TABLE emp(id INT, name TEXT);
INSERT INTO emp VALUES (1,'ram'),(2,'raj');
```

---

### 🔗 Step 7: Create Publication (Publisher)

```sql
CREATE PUBLICATION mypub FOR TABLE emp;
```

Check:

```sql
SELECT * FROM pg_publication;
```

Exit:

```bash
\q
```

---

### 🔧 Step 8: Configure Subscriber

Enter:

```bash
podman exec -it pg-subscriber psql -U postgres
```

Create same table (MANDATORY):

```sql
CREATE TABLE emp(id INT, name TEXT);
```

---

### 🔗 Step 9: Create Subscription (Subscriber)

```sql
CREATE SUBSCRIPTION mysub
CONNECTION 'host=pg-publisher port=5432 user=postgres password=postgres dbname=postgres'
PUBLICATION mypub;
```

---

### ✅ Step 10: Verify Replication

On Subscriber:

```sql
SELECT * FROM emp;
```

👉 You should see data from publisher

---

### 🧪 Step 11: Real Test

On Publisher:

```sql
INSERT INTO emp VALUES (3,'krishna');
```

On Subscriber:

```sql
SELECT * FROM emp;
```

👉 Data should replicate

---

### 🔍 Monitoring Commands

On Publisher:

```sql
SELECT * FROM pg_publication;
SELECT * FROM pg_replication_slots;
```

On Subscriber:

```sql
SELECT * FROM pg_subscription;
SELECT * FROM pg_stat_subscription;
```

---

### ⚠️ Common Issues

Table not replicating:

* Table not in publication

Permission error:

* Wrong user/password

No data:

* Table not created in subscriber

---

### 🧠 Key Understanding

* Logical replication works at table level
* Uses publications and subscriptions
* Requires wal_level=logical
* Does not require full cluster copy

---

### 🚀 Practice Ideas

* Add multiple tables to publication
* Test DELETE and UPDATE
* Drop and recreate subscription
* Create logical replication slot manually

---

This is production-level logical replication setup.

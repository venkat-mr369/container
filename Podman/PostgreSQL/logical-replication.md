
**Already we have 2 containers (primary + standby)**

But here’s the important part:

👉 **Logical replication is DIFFERENT from streaming replication**
👉 So you must **treat both containers as independent databases**

---

### 🧠 What changes in your current setup

Right now:

```text
pg-primary  → streaming → pg-standby
```

For logical:

```text
pg-primary (publisher) → pg-standby (subscriber)
```

👉 BUT:

* Standby must NOT be in recovery mode ❌
* It must behave like a normal DB ✅

---

### ❗ Step 0: Break streaming replication (VERY IMPORTANT)

👉 On standby container:

```bash
podman exec -it pg-standby bash
```

Stop Postgres:

```bash
pg_ctl stop -D /var/lib/postgresql/data
```

Remove recovery:

```bash
rm /var/lib/postgresql/data/standby.signal
```

Start again:

```bash
pg_ctl start -D /var/lib/postgresql/data
```

---

## ✅ Verify (STANDBY)

```sql
SELECT pg_is_in_recovery();
```

👉 Must be:

```text
false
```

✔️ Now it’s normal DB → ready for logical replication

---

# 🔧 Step 1: Enable logical on PRIMARY

```bash
podman exec -it pg-primary bash
```

Edit:

```bash
nano /var/lib/postgresql/data/postgresql.conf
```

Add:

```conf
wal_level=logical
max_replication_slots=10
max_wal_senders=10
```

Restart:

```bash
exit
podman restart pg-primary
```

---

# 🔧 Step 2: Allow connection

Edit pg_hba.conf (PRIMARY):

```conf
host all all 0.0.0.0/0 md5
```

Restart again.

---

# 🧪 Step 3: Create table (PRIMARY)

```bash
podman exec -it pg-primary psql -U postgres
```

```sql
CREATE TABLE emp(id INT, name TEXT);
INSERT INTO emp VALUES (1,'ram'),(2,'raj');
```

---

# 🔗 Step 4: Create publication (PRIMARY)

```sql
CREATE PUBLICATION mypub FOR TABLE emp;
```

---

# 🧪 Step 5: Prepare subscriber (STANDBY)

```bash
podman exec -it pg-standby psql -U postgres
```

👉 Create same table:

```sql
CREATE TABLE emp(id INT, name TEXT);
```

---

# 🔗 Step 6: Create subscription (STANDBY)

```sql
CREATE SUBSCRIPTION mysub
CONNECTION 'host=pg-primary port=5432 user=postgres password=postgres dbname=postgres'
PUBLICATION mypub;
```

---

# ✅ Step 7: Verify

On standby:

```sql
SELECT * FROM emp;
```

👉 You should see:

```text
1 | ram
2 | raj
```

---

# 🧪 Step 8: Test

On primary:

```sql
INSERT INTO emp VALUES (3,'krishna');
```

On standby:

```sql
SELECT * FROM emp;
```

👉 Data will come ✅

---

# 🧠 Important clarity

| Streaming Replication | Logical Replication     |
| --------------------- | ----------------------- |
| standby = read-only   | subscriber = read-write |
| full DB copy          | table-level             |
| recovery mode         | normal DB               |

---

# ⚠️ Biggest mistake people do

👉 They try logical replication on **standby in recovery mode**

That will NEVER work ❌

---

# 🎯 Final understanding

You are now using:

* same containers ✅
* but switching mode from **physical → logical**

---


* run BOTH (streaming + logical together 🔥)
* or **real interview difference with use cases**

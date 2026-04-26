Good — let’s do **PROMOTION (failover)** cleanly 👍
This is a **very important interview + real DBA step**.

---

# 🧠 What is Promote?

👉 You convert **standby → primary**

```text id="s0sjmp"
Before:
Primary (pg-primary) → Standby (pg-standby)

After promote:
Standby becomes NEW PRIMARY
```

---

# 🚀 Step-by-step PROMOTE

## 🔹 Step 1: Go to standby container

```bash id="d4e3q4"
podman exec -it pg-standby bash
```

---

## 🔹 Step 2: Switch to postgres user

```bash id="26jbqn"
su - postgres
```

---

## 🔹 Step 3: Run promote command

```bash id="t8dzxg"
/usr/lib/postgresql/16/bin/pg_ctl promote -D /var/lib/postgresql/data
```

---

# ✅ Step 4: Verify (VERY IMPORTANT)

### On standby (now new primary):

```sql id="fyxb7q"
SELECT pg_is_in_recovery();
```

👉 Expected:

```text id="zj73k1"
false
```

✔️ Means → no longer standby
✔️ Now it is PRIMARY

---

# 🔍 Step 5: Check old primary

On old primary:

```sql id="r3um79"
SELECT client_addr, state FROM pg_stat_replication;
```

👉 Expected:

```text id="jpbp8o"
(0 rows)
```

👉 Because:

```text id="gdd9kq"
Old primary is now disconnected
```

---

# 🧠 What just happened internally

When you ran:

```bash id="uvt7af"
pg_ctl promote
```

PostgreSQL did:

1. Removed recovery mode
2. Stopped WAL receiver
3. Started generating WAL
4. Became independent PRIMARY

---

# 🔥 Visual

```text id="79jc72"
Before:
pg-primary → pg-standby

After:
pg-standby (NEW PRIMARY)
pg-primary (OLD / unused)
```

---

# 🧪 Test it

## On new primary (old standby):

```sql id="yx5q3t"
INSERT INTO emp VALUES (200,'after_promote');
```

👉 It should work ✅ (now writable)

---

# ⚠️ Important warning

👉 After promote:

```text id="8hw1q7"
Replication is BROKEN (expected)
```

👉 Because:

* both are independent now
* timelines diverged

---

# 🎯 Interview answer

👉 *“Promotion is the process of converting a standby into a primary using pg_ctl promote, typically during failover.”*

---

# 💡 Next step (VERY IMPORTANT)

Now real DBA work:

👉 Convert old primary → standby again using **pg_rewind**

---
Perfect — let’s do a **clean, end-to-end failover → pg_rewind → rejoin** flow. Follow it step by step and you’ll have a rock-solid understanding.

---

### 🐘 Scenario Setup

```text
pg-primary   → OLD PRIMARY
pg-standby   → STANDBY
```

After failover:

```text
pg-standby   → NEW PRIMARY
pg-primary   → OLD PRIMARY (needs rewind)
```

---

# 🔥 Phase 1: Failover (Promote Standby)

## ▶️ On pg-standby

```bash
podman exec -it pg-standby bash
su - postgres
/usr/lib/postgresql/16/bin/pg_ctl promote -D /var/lib/postgresql/data
```

---

## ✅ Verify

```sql
SELECT pg_is_in_recovery();
```

👉 Output:

```text
false
```

✔️ pg-standby is now **NEW PRIMARY**

---

# 🔥 Phase 2: Old Primary is now broken

👉 pg-primary still thinks it's primary
👉 Timeline mismatch happens

---

## ❗ Stop old primary (VERY IMPORTANT)

```bash
podman exec -it pg-primary bash
su - postgres
/usr/lib/postgresql/16/bin/pg_ctl stop -D /var/lib/postgresql/data
```

---

# 🔥 Phase 3: Run pg_rewind

👉 Run this on **OLD PRIMARY (pg-primary)**

```bash
/usr/lib/postgresql/16/bin/pg_rewind \
  --target-pgdata=/var/lib/postgresql/data \
  --source-server="host=pg-standby user=replicator password=replica123 dbname=postgres"
```

---

## 🧠 What happens here

* Compares OLD PRIMARY vs NEW PRIMARY
* Copies only changed blocks
* Fixes timeline

👉 Fast ⚡ (no full backup)

---

# 🔥 Phase 4: Convert old primary → standby

## ▶️ On pg-primary

### Create standby mode

```bash
touch /var/lib/postgresql/data/standby.signal
```

---

### Add connection info

```bash
nano /var/lib/postgresql/data/postgresql.auto.conf
```

Add:

```conf
primary_conninfo = 'host=pg-standby user=replicator password=replica123'
```

---

# 🔥 Phase 5: Start old primary

```bash
/usr/lib/postgresql/16/bin/pg_ctl start -D /var/lib/postgresql/data
```

---

# 🔍 Phase 6: Final Verification

## ▶️ On NEW PRIMARY (pg-standby)

```sql
SELECT client_addr, state FROM pg_stat_replication;
```

👉 Expected:

```text
pg-primary → streaming
```

---

## ▶️ On OLD PRIMARY (now standby)

```sql
SELECT pg_is_in_recovery();
```

👉 Output:

```text
true
```

---

## ▶️ Check WAL receiver

```sql
SELECT status FROM pg_stat_wal_receiver;
```

👉 Output:

```text
streaming
```

---

# 🧪 Final Test

## On NEW PRIMARY

```sql
INSERT INTO emp VALUES (999,'rewind_test');
```

---

## On OLD PRIMARY (standby)

```sql
SELECT * FROM emp WHERE id=999;
```

👉 Row should appear ✅

---

# 🧠 Full Flow Summary

```text
1. Standby promoted → becomes primary
2. Old primary stopped
3. pg_rewind run on old primary
4. Convert old primary to standby
5. Start and rejoin replication
```

---

# 🎯 Interview Answer (Perfect)

👉 *“During failover, standby is promoted to primary. The old primary cannot rejoin due to timeline divergence, so we use pg_rewind to synchronize it quickly and reattach it as a standby.”*

---

# 🔥 Golden Rule

```text
Failover → Promote standby
Rejoin old primary → pg_rewind
```

---

If you want next level:

👉 I can give:

* split-brain scenario ⚠️
* synchronous replication failover
* Patroni automated failover 🔥


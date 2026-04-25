---

### 🐘 PostgreSQL Replication Slots — Real DBA Scenarios 

---

### 🧠 What is Replication Slot (simple)

A replication slot ensures WAL is **NOT deleted** until standby consumes it.

👉 Good: prevents data loss
👉 Bad: can **fill disk** if standby is down

---

### 🔍 Check Replication Slots (PRIMARY)

```sql
SELECT slot_name, active, restart_lsn FROM pg_replication_slots;
```

---

### Scenario 1: WAL Files Filling Disk (Standby Down)

### 💡 Problem

Standby is stopped → WAL not consumed → disk fills

---

### ▶️ Simulate

👉 **Run on PRIMARY**

```sql
SELECT * FROM pg_create_physical_replication_slot('test_slot');
```

Generate WAL:

```sql
CREATE TABLE t2 AS SELECT generate_series(1,1000000);
```

👉 **Run on HOST (stop standby)**

```bash
podman stop pg-standby
```

---

### 🔍 Check Issue (PRIMARY)

```sql
SELECT slot_name, active FROM pg_replication_slots;
```

👉 active = false ❌

```sql
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) 
AS wal_retained 
FROM pg_replication_slots;
```

👉 WAL keeps increasing 🔥

---

### ✅ Fix

👉 Option 1 (best):

```bash
podman start pg-standby
```

👉 Option 2 (careful ⚠️):

```sql
SELECT pg_drop_replication_slot('test_slot');
```

---

### Scenario 2: Orphan Slot (Standby Deleted)

### 💡 Problem

Standby removed but slot still exists → WAL grows forever

---

### ▶️ Simulate

👉 Delete standby:

```bash
podman rm -f pg-standby
```

---

### 🔍 Check (PRIMARY)

```sql
SELECT slot_name, active FROM pg_replication_slots;
```

👉 active = false ❌

---

### ✅ Fix (PRIMARY)

```sql
SELECT pg_drop_replication_slot('test_slot');
```

---

### Scenario 3: Replication Lag + WAL Growth

### 💡 Problem

Standby slow → lag increases → WAL accumulation

---

### ▶️ Generate load (PRIMARY)

```sql
INSERT INTO t1 SELECT generate_series(1,500000);
```

---

### 🔍 Check lag (PRIMARY)

```sql
SELECT client_addr, write_lag, flush_lag, replay_lag 
FROM pg_stat_replication;
```

---

### 🔍 Check WAL retained (PRIMARY)

```sql
SELECT slot_name, 
pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) 
FROM pg_replication_slots;
```

---

### 🔍 Check delay (STANDBY)

```sql
SELECT now() - pg_last_xact_replay_timestamp();
```
### To Verify 

```sql
---On Primary
SELECT pg_current_wal_lsn();

---On Secondary
SELECT 
  pg_last_wal_receive_lsn(),
  pg_last_wal_replay_lsn();
```
---

### ✅ Fix

* Increase standby CPU/RAM
* Improve network
* Tune WAL parameters

---

# 🔥 Interview Killer Points

* Slots **prevent WAL deletion**
* Slots can cause **disk full issues**
* Always monitor:

  * `pg_replication_slots`
  * `pg_stat_replication`
* Drop unused slots immediately

---

# 🚀 Real DBA Checklist

👉 **Run on PRIMARY**

```sql
SELECT * FROM pg_stat_replication;
SELECT * FROM pg_replication_slots;
SELECT pg_current_wal_lsn();
```

👉 **Run on STANDBY**

```sql
SELECT pg_is_in_recovery();
SELECT pg_last_xact_replay_timestamp();
```

---

## 🧠 Final Clarity

If interviewer asks:

👉 *“What is danger of replication slots?”*

You say:

➡️ “If standby is down or slow, WAL files accumulate and can fill disk because slots prevent deletion.”

---

If you want next level, I can give:

👉 **“Disk full recovery scenario step-by-step”**
👉 **“Slot vs wal_keep_size difference (very important interview)”**

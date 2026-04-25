### 🐘 PostgreSQL Replication Slots — Real DBA Scenarios

### 🧠 What is Replication Slot (simple)

A replication slot ensures WAL is NOT deleted until standby consumes it.

👉 Good: prevents data loss
👉 Bad: can fill disk if standby is down

---

### 🔍 Check Replication Slots

```sql
SELECT slot_name, active, restart_lsn FROM pg_replication_slots;
```

---

## 🔥 Scenario 1: WAL Files Filling Disk (Standby Down)

### Problem

Standby is stopped → WAL not consumed → disk fills

---

### Simulate

On Primary:

```sql
SELECT * FROM pg_create_physical_replication_slot('test_slot');
```

Generate load:

```sql
CREATE TABLE t1 AS SELECT generate_series(1,1000000);
```

Stop standby container.

---

### Check issue

```sql
SELECT slot_name, active FROM pg_replication_slots;
```

```sql
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained FROM pg_replication_slots;
```

👉 WAL keeps increasing 🔥

---

### Fix

Option 1: Start standby

Option 2: Drop slot (careful ⚠️)

```sql
SELECT pg_drop_replication_slot('test_slot');
```

---

## 🔥 Scenario 2: Orphan Slot (Standby Removed but Slot Exists)

### Problem

Standby deleted but slot still exists → WAL grows forever

---

### Check

```sql
SELECT slot_name, active FROM pg_replication_slots;
```

👉 active = false

---

### Fix

```sql
SELECT pg_drop_replication_slot('test_slot');
```

---

## 🔥 Scenario 3: Slot Not Used by Standby

### Problem

Slot created but standby not configured to use it

---

### Check standby config

```bash
grep primary_slot_name /var/lib/postgresql/data/postgresql.auto.conf
```

👉 If empty → slot unused

---

### Fix

Add:

```conf
primary_slot_name = 'test_slot'
```

Restart standby

---

## 🔥 Scenario 4: Replication Lag Due to Slot

### Problem

Standby slow → lag increases → WAL accumulation

---

### Check lag

```sql
SELECT client_addr, write_lag, flush_lag, replay_lag FROM pg_stat_replication;
```

---

### Check slot lag

```sql
SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) FROM pg_replication_slots;
```

---

### Fix

* Improve standby performance
* Increase resources
* Tune network

---

## 🔥 Interview Killer Points

* Slots prevent WAL deletion
* Slots can cause disk full
* Always monitor pg_replication_slots
* Drop unused slots immediately

---

### 🚀 Real DBA Checklist

```sql
SELECT * FROM pg_stat_replication;
SELECT * FROM pg_replication_slots;
SELECT pg_current_wal_lsn();
```

---

This is real production troubleshooting knowledge.

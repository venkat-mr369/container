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


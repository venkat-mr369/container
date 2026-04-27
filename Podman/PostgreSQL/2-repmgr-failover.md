**automatic failover using `repmgrd`** and then test it live 🔥

---

### 1. Enable Automatic Failover (repmgrd)

You need to run `repmgrd` on:

* rep-primary
* rep-standby1
* rep-standby2
  (❌ not required on witness)

---

### 🔹 Step 1: Update repmgr.conf (on ALL nodes)

Edit:

```bash
nano /etc/repmgr.conf
```

Add these lines:

```ini
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf'
follow_command='repmgr standby follow -f /etc/repmgr.conf'
log_level=INFO
monitoring_history=yes
```
--verify permissions
```bash
root@00df59b99e84:/# ls -l /etc/repmgr.conf
-rw------- 1 postgres postgres 324 Apr 26 12:16 /etc/repmgr.conf
```
If missing
```bash
chown postgres:postgres /etc/repmgr.conf
chmod 600 /etc/repmgr.conf
```

---

### 🔹 Step 2: Start repmgrd (as postgres)

Run on **each node (primary + both standby's)**:

```bash
repmgrd -f /etc/repmgr.conf -d
```

👉 `-d` = run as daemon

---

### 🔹 Step 3: Verify daemon running

```bash
ps -ef | grep repmgrd
```

---

### 🔥 2. LIVE FAILOVER TEST (Important)

Now the real test 💥

---

### 🔴 Step 1: Stop PRIMARY (simulate crash)

From host:

```bash id="q1r7nm"
podman stop rep-primary
```

---

## 🔍 Step 2: Watch logs (on standby1)

```bash id="z5x2kl"
podman exec -it rep-standby1 bash
su - postgres
```

Check logs:

```bash id="v2m8xp"
tail -f /var/lib/postgresql/data/log/*
```

👉 You’ll see:

```text id="n4t8yc"
promoting standby to primary
```

---

## 🔹 Step 3: Verify cluster

Run:

```bash id="k8d2zw"
repmgr cluster show
```

---

# ✅ Expected Result

```text id="p6w9rs"
rep-standby1   primary   🔥 (promoted)
rep-standby2   standby   (following new primary)
rep-witness    witness
rep-primary    failed
```

---

# 🧠 What happened internally

1. Primary stopped
2. Standby detected failure
3. Witness helped quorum decision
4. One standby promoted
5. Other standby followed

👉 **Zero manual intervention = HA success**

---

# 🔁 3. Bring Old Primary Back (Important)

After failover:

```bash id="x7m4nv"
podman start rep-primary
```

Then:

```bash id="b3k9pw"
repmgr node rejoin -f /etc/repmgr.conf --force-rewind
```

👉 This makes old primary → standby

---

# 🔥 You achieved (very important)

✔ Multi-node replication
✔ Witness-based quorum
✔ Automatic failover
✔ Self-healing cluster

👉 This is **real production-level DBA skill**

---

# 🚀 Next (if you want)

We can go deeper:

👉 Pgpool-II (load balancing + routing)
👉 Grafana monitoring
👉 Kubernetes + Patroni comparison

---

Run failover once and tell me what happened — I’ll help you analyze it like an interviewer would 👍

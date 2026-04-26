**repmgr-based PostgreSQL HA lab in Podman**  👍

---

### 🔹 1. Container Naming 

Use these names:

```
rep-primary
rep-standby1
rep-standby2
rep-witness   (optional but recommended)
pgpool        (later step)
```

---

### 🔹 2. Create Network

```bash
podman network create pg-rep-net
```

---

### 🔹 3. Create Volumes

```bash
podman volume create rep-primary-data
podman volume create rep-standby1-data
podman volume create rep-standby2-data
```

---

### 🔹 4. Start Primary Container

```bash
podman run -d --name rep-primary --network pg-rep-net -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -v rep-primary-data:/var/lib/postgresql/data docker.io/postgres:15
```

---

### 🔹 5. Install repmgr inside Primary

```bash
podman exec -it rep-primary bash
```

Inside container:

```bash
apt update
apt install -y repmgr
```

---

### 🔹 6. Configure Primary (repmgr)

Edit:

```bash
nano /etc/repmgr.conf
```

Add:

```
node_id=1
node_name=rep-primary
conninfo='host=rep-primary user=repmgr dbname=repmgr password=repmgr'
data_directory='/var/lib/postgresql/data'
```

---

# 🔹 7. Create repmgr User & DB

Login to postgres:

```bash
psql -U postgres
```

Run:

```sql
CREATE USER repmgr WITH REPLICATION PASSWORD 'repmgr';
CREATE DATABASE repmgr OWNER repmgr;
```

---

# 🔹 8. Register Primary

```bash
repmgr primary register
```

---

# 🔹 9. Create Standby Containers

### Standby 1

```bash
podman run -d --name rep-standby1 \
  --network pg-rep-net \
  -e POSTGRES_PASSWORD=postgres \
  -v rep-standby1-data:/var/lib/postgresql/data \
  docker.io/postgres:15
```

### Standby 2

```bash
podman run -d --name rep-standby2 \
  --network pg-rep-net \
  -e POSTGRES_PASSWORD=postgres \
  -v rep-standby2-data:/var/lib/postgresql/data \
  docker.io/postgres:15
```

---

# 🔹 10. Clone Standby (Important Step)

Enter standby:

```bash
podman exec -it rep-standby1 bash
```

Install repmgr:

```bash
apt update && apt install -y repmgr
```

Stop postgres:

```bash
pg_ctlcluster 15 main stop
```

Clone:

```bash
repmgr -h rep-primary -U repmgr -d repmgr standby clone
```

Start:

```bash
pg_ctlcluster 15 main start
```

Register:

```bash
repmgr standby register
```

👉 Repeat same for **rep-standby2**

---

# 🔹 11. Verify Cluster

On primary:

```bash
repmgr cluster show
```

You should see:

```
rep-primary    primary
rep-standby1   standby
rep-standby2   standby
```

---

# 🔹 12. (Optional but Recommended) Witness Node

Name:

```
rep-witness
```

Used to avoid split-brain.

---

# 🔥 Next Step (Tell me)

Once this is done, I’ll help you with:

👉 automatic failover (`repmgrd`)
👉 Pgpool-II setup
👉 Grafana monitoring

We can make this **production-level lab** step by step.

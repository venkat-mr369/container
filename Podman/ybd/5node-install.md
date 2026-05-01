## The big architectural difference to internalize first

CockroachDB ran **one process per node** (the `cockroach` binary).

YugabyteDB runs **two processes per node**:

| Process | Role | CockroachDB equivalent |
|---|---|---|
| **YB-Master** | Cluster metadata, tablet placement, DDL, schema, leader election for masters | Built into the single `cockroach` binary |
| **YB-TServer** | Actual data storage, query execution, client connections | Also built into the single `cockroach` binary |

Why two processes? YugabyteDB's design philosophy: keep the **control plane** (metadata, decisions) and the **data plane** (storage, queries) clearly separated. CockroachDB collapses them. Both are valid choices.

Important detail: with replication factor 3, **only 3 nodes run YB-Master**. The other 2 nodes only run YB-TServer. Master count = RF, by design — they form a Raft quorum among themselves. TServer count = number of nodes.

For 5 nodes with RF=3, you'll see:
- All 5 nodes run YB-TServer.
- 3 of them also run YB-Master.

We'll let `yugabyted` (the official cluster utility, similar to how you used `cockroach`) figure out the placement automatically.

---

## Ports you need to know

| Port | Purpose | CockroachDB analog |
|---|---|---|
| **5433** | YSQL (PostgreSQL-compatible SQL) | 26257 |
| 9042 | YCQL (Cassandra-compatible) | (none) |
| **7000** | YB-Master web UI | 8080 (DB Console) |
| 9000 | YB-TServer web UI | (combined into 8080) |
| **15433** | `yugabyted` cluster UI (newer, cleaner view) | 8080 |
| 7100 | Master internal RPC | 26257 |
| 9100 | TServer internal RPC | 26257 |

You'll publish 5433, 7000, 9000, and 15433 from node 1 to your host. The internal RPC ports stay on the Podman network.

---

## Step 1 — Pull the YugabyteDB image (pinned)

Lesson from your CockroachDB experience: **always pin the version**. We'll use the latest 2025.2 LTS patch:

```powershell
podman pull yugabytedb/yugabyte:2025.2.2.1
```

Verify:

```powershell
podman images | findstr yugabyte
```

(`findstr` is the PowerShell equivalent of Linux `grep`.)

## Step 2 — Create a Podman network

```powershell
podman network ls
podman network inspect venkat-net
```

Verify:

```powershell
podman network ls
```

## Step 3 — Create persistent volumes (one per node)

YugabyteDB stores its data in `/home/yugabyte/yb_data` inside the container by convention. We'll mount a volume there for each node.

```powershell
podman volume create yb1-data
podman volume create yb2-data
podman volume create yb3-data
podman volume create yb4-data
podman volume create yb5-data
```

## Step 4 — Start the seed node (yb1)

This first node is special — it doesn't `--join` anything because it *is* the cluster's starting point. Subsequent nodes will join it. Same pattern as CockroachDB, but the seed node here actually starts the cluster immediately rather than waiting for an `init` step.

**One-line PowerShell command:**

```powershell
podman run -d --name=yb1 --hostname=yb1 --net=venkat-net -p 5433:5433 -p 7000:7000 -p 9000:9000 -p 15433:15433 -p 9042:9042 -v yb1-data:/home/yugabyte/yb_data yugabytedb/yugabyte:2025.2.1.0-b141 bin/yugabyted start --base_dir=/home/yugabyte/yb_data --advertise_address=yb1 --fault_tolerance=none --background=false
```

What each new flag means:
- `bin/yugabyted start` — the cluster utility (think of it as `cockroach start` plus auto-init).
- `--base_dir` — where data, logs, and config live inside the container.
- `--advertise_address=yb1` — what hostname this node tells peers to use when contacting it. Critical for a multi-node setup; without it, the node tells peers "reach me at localhost," which fails from other containers.
- `--fault_tolerance=none` — for a single-host learning cluster. In production, you'd use `zone`, `region`, or `cloud` to enable rack-aware placement.
- `--background=false` — keep the process in the foreground so Podman's `-d` properly tracks it. (Without this, Podman thinks the container exited.)

Verify it started:

```powershell
podman ps
podman logs yb1
```

Wait ~10 seconds before starting the next nodes — let the seed fully come up.

## Step 5 — Start the 4 joining nodes (yb2 through yb5)

Each of these uses `--join=yb1` to point at the seed. They don't publish ports to the host (only yb1 does, for the UI).

**Node 2:**

```powershell
podman run -d --name=yb2 --hostname=yb2 --net=venkat-net -v yb2-data:/home/yugabyte/yb_data yugabytedb/yugabyte:2025.2.1.0-b141 bin/yugabyted start --base_dir=/home/yugabyte/yb_data --advertise_address=yb2 --join=yb1 --fault_tolerance=none --background=false
```

**Node 3:**

```powershell
podman run -d --name=yb3 --hostname=yb3 --net=venkat-net -v yb3-data:/home/yugabyte/yb_data yugabytedb/yugabyte:2025.2.1.0-b141 bin/yugabyted start --base_dir=/home/yugabyte/yb_data --advertise_address=yb3 --join=yb1 --fault_tolerance=none --background=false
```

**Node 4:**

```powershell
podman run -d --name=yb4 --hostname=yb4 --net=venkat-net -v yb4-data:/home/yugabyte/yb_data yugabytedb/yugabyte:2025.2.1.0-b141 bin/yugabyted start --base_dir=/home/yugabyte/yb_data --advertise_address=yb4 --join=yb1 --fault_tolerance=none --background=false
```

**Node 5:**

```powershell
podman run -d --name=yb5 --hostname=yb5 --net=venkat-net -v yb5-data:/home/yugabyte/yb_data yugabytedb/yugabyte:2025.2.1.0-b141 bin/yugabyted start --base_dir=/home/yugabyte/yb_data --advertise_address=yb5 --join=yb1 --fault_tolerance=none --background=false
```

Wait about 30 seconds for everything to converge, then verify:

```powershell
podman ps
```

You should see all 5 containers running.

## Step 6 — Check cluster status

```powershell
podman exec -it yb1 bin/yugabyted status --base_dir=/home/yugabyte/yb_data
```

This should show all 5 nodes joined. Compare to:
- CockroachDB: `cockroach node status --insecure --host=roach1:26257`
- Postgres: `SELECT * FROM pg_stat_replication;`

## Step 7 — Open the UIs (this is where it gets interesting)

YugabyteDB gives you **three** different web UIs, each with a different focus. Open them in your browser:

**Modern unified UI (start here):**
```
http://localhost:15433
```
This is the newer `yugabyted` UI showing cluster overview, nodes, performance.

**YB-Master UI (cluster control plane):**
```
http://localhost:7000
```
Shows tablet servers, namespaces, tablets, master leader, replication info. This is the closest analog to CockroachDB's DB Console for cluster-wide info.

**YB-TServer UI (this node's data plane):**
```
http://localhost:9000
```
Shows tablets on this specific node, query execution, RPC stats.

Compare to CockroachDB which has all of this on a single port (8080). Some people prefer one consolidated UI; others prefer the separation. You'll form your own opinion.

## Step 8 — Connect with the SQL shell

YugabyteDB's SQL shell is `ysqlsh`, which is **literally a fork of PostgreSQL's `psql`**. So if you've ever used `psql`, you already know `ysqlsh`.

```powershell
podman exec -it yb1 bin/ysqlsh -h yb1 -U yugabyte
```

Note the differences from CockroachDB:
- `ysqlsh` not `cockroach sql`
- `-h yb1` (host) and `-U yugabyte` (default user) — Postgres-style flags
- Default port 5433, not 26257

Once in the shell, try the same exercises:

```sql
CREATE DATABASE yes;
\c yes
CREATE TABLE accounts (id INT PRIMARY KEY, balance DECIMAL);
INSERT INTO accounts VALUES (1, 1000.50), (2, 250.00);
SELECT * FROM accounts;
```

Notice `\c bank` — that's the psql meta-command to switch databases. Pure Postgres ergonomics. CockroachDB's `USE bank;` is more SQL-Server-style.

Verify replication by querying through a different node:

```powershell
podman exec -it yb3 bin/ysqlsh -h yb3 -U yugabyte -d bank -c "SELECT * FROM accounts;"
```

Same data, different node — replication working.

## Step 9 — Inspect the cluster from SQL (the equivalent of crdb_internal)

This is the parallel to all the `crdb_internal` digging you did. YugabyteDB exposes cluster info through:

```sql
-- See all servers in the cluster
SELECT * FROM yb_servers();

-- Standard PostgreSQL catalog still works (because YSQL IS Postgres)
SELECT datname FROM pg_database;
SELECT * FROM pg_stat_activity;

-- Tablet (range equivalent) properties for a table
SELECT * FROM yb_table_properties('accounts'::regclass);
```

The mental map:

| Concept | CockroachDB | YugabyteDB |
|---|---|---|
| Cluster topology | `crdb_internal.gossip_nodes` | `yb_servers()` function |
| Connection list | `crdb_internal.cluster_queries` | `pg_stat_activity` (real Postgres view) |
| Data shards | "ranges" → `crdb_internal.ranges` | "tablets" → `yb_table_properties()` |
| Internal access restriction | `allow_unsafe_internals` | No equivalent; YugabyteDB inherits Postgres's catalog as supported surface |

The big advantage YugabyteDB has here for learning: **all standard PostgreSQL `pg_catalog` views and `\d`/`\dt` meta-commands work**, because the query layer is forked from Postgres 15. So your Postgres knowledge transfers directly.

## Step 10 — Test fault tolerance

Same exercise as you did on CockroachDB:

```powershell
podman stop yb3
```

Open `http://localhost:7000` and watch yb3 turn red. Run a query through yb1 — it still works. Bring yb3 back:

```powershell
podman start yb3
```

It rejoins automatically. Same Raft magic, different implementation.

---

## Day-to-day commands cheat sheet

```powershell
# Stop all nodes (data persists in volumes)
podman stop yb1 yb2 yb3 yb4 yb5

# Start them back up
podman start yb1 yb2 yb3 yb4 yb5

# Tail logs
podman logs -f yb1

# Cluster status from yugabyted
podman exec -it yb1 bin/yugabyted status --base_dir=/home/yugabyte/yb_data

# Drop into bash inside a container
podman exec -it yb1 bash

# Wipe everything and start over
podman stop yb1 yb2 yb3 yb4 yb5
podman rm yb1 yb2 yb3 yb4 yb5
podman volume rm yb1-data yb2-data yb3-data yb4-data yb5-data
podman network rm venkat-net
```

---

## Direct comparison: what you've now built twice

| | CockroachDB cluster | YugabyteDB cluster |
|---|---|---|
| Container count | 5 | 5 |
| Processes per container | 1 (cockroach) | 2 (yb-master + yb-tserver, managed by yugabyted) |
| Master nodes | All 5 equal | Only 3 of 5 (= replication factor) |
| Default RF | 3 | 3 |
| Init step | Manual `cockroach init` | Automatic (yugabyted does it) |
| SQL port | 26257 | 5433 |
| UI port | 8080 (one UI) | 7000 + 9000 + 15433 (three UIs) |
| SQL shell | `cockroach sql` | `ysqlsh` (forked psql) |
| Postgres compatibility | Reimplemented | Forked source code |
| Wire protocol | Postgres | Postgres |
| Data shards called | "ranges" | "tablets" |
| Storage engine | Pebble (Go) | DocDB (RocksDB-based, C++) |
| Language | Go | C++ |
| License | BSL | Apache 2.0 |

Both speak Postgres wire protocol — meaning the **same Python code, same drivers, same connection pools, same HAProxy** that you'd use for CockroachDB also works here. Only the connection string changes:

```
# CockroachDB
postgresql://root@localhost:26257/bank?sslmode=disable

# YugabyteDB
postgresql://yugabyte@localhost:5433/bank?sslmode=disable
```

---

## Common gotchas specific to YugabyteDB on Podman

If yb1 starts but the others fail to join, check `podman logs yb2` for messages about being unable to reach `yb1:7100`. Usually means yb1 hasn't fully come up yet — wait longer between starting nodes. The first node needs ~15-20 seconds before it's ready to accept joins.

If you skip `--advertise_address`, nodes will tell each other to connect via `localhost`, which works inside one container but not across containers. This is the most common silent failure on Podman/Docker setups.

The `--fault_tolerance=none` flag is fine for learning. For production, you'd set it to `zone` and pass `--cloud_location=cloud1.region1.zone1` to each node (varying the zone) so the placement engine spreads replicas across zones intelligently.

---

Try the steps in order, and once `podman ps` shows all 5 nodes up, paste the output of:

```powershell
podman exec -it yb1 bin/yugabyted status --base_dir=/home/yugabyte/yb_data
```



Great learning project. CockroachDB on Podman is an excellent way to understand distributed databases, Raft consensus, and replication. I'll walk you through every step with explanations of *why* each piece matters, not just the commands. We'll build a 5-node **insecure** cluster (insecure = no TLS certs, simpler for learning; never use this in production).

---

## Concepts you should understand first

Before commands, here's what we're actually building:

- **Node** = one running `cockroach` process. We'll run 5 of them, each in its own Podman container.
- **Cluster** = the 5 nodes joined together, acting as one logical database.
- **Two ports per node**: `26257` is the SQL/internal port (where clients and other nodes talk), `8080` is the DB Console (the web UI).
- **`--join` flag** tells a node which other nodes exist so they can find each other (gossip protocol).
- **`cockroach init`** is run *once* after all nodes are started — it bootstraps the cluster (creates the cluster ID, Raft groups, system tables).
- **Replication factor**: by default each piece of data is replicated to 3 nodes. With 5 nodes you can raise it to 5 for better fault tolerance — we'll do that at the end.
- **Volumes**: each node needs its own persistent storage, otherwise restarting a container wipes its data.

---

## Step 1 — Verify Podman is installed and working

```bash
podman --version
podman info
```

You should see Podman 5.x. The `podman info` output shows the storage driver, network backend (should be `netavark` on Podman 4+/5+), and rootless status. If this fails, install Podman first via your distro's package manager.

A quick sanity check that containers can run:

```bash
podman run --rm hello-world
```

---

## Step 2 — Pull the CockroachDB image

```bash
podman pull cockroachdb/cockroach:latest
```

You can pin to a specific version like `cockroachdb/cockroach:v25.4.2` for reproducibility — pinning is good practice because `latest` will change under you. Check the [official tags page](https://hub.docker.com/r/cockroachdb/cockroach/tags) for the current stable version.

Verify the pull:

```bash
podman images | grep cockroach
```

---

## Step 3 — Create a dedicated Podman network

Why: each container gets its own IP on this network, and they can resolve each other by container name (DNS). Without this, nodes would have to use IPs that change.

```bash
podman network create roachnet
```

Verify:

```bash
podman network ls
podman network inspect roachnet
```

Look at the `subnet` field — that's the IP range your containers will get. Typically something like `10.89.0.0/24`.

---

## Step 4 — Create persistent volumes (one per node)

Why: container filesystems are ephemeral. The CockroachDB data files (`/cockroach/cockroach-data` inside the container) must live on a volume so node restarts don't lose data.

```bash
podman volume create roach1-data
podman volume create roach2-data
podman volume create roach3-data
podman volume create roach4-data
podman volume create roach5-data
```

Verify:

```bash
podman volume ls
```

---

## Step 5 — Start the 5 nodes

We start each node as a detached container. Important flags broken down:

- `--name roach1` → container name (also DNS hostname on `roachnet`).
- `--hostname roach1` → hostname inside the container.
- `--net=roachnet` → attach to our bridge network.
- `-p 26257:26257 -p 8080:8080` → publish ports to the host (only on roach1, so we have one stable entry point).
- `-v roach1-data:/cockroach/cockroach-data` → mount the volume.
- `cockroach start` → multi-node start command (NOT `start-single-node`).
- `--insecure` → no TLS (learning only).
- `--listen-addr=roach1:26257` → which interface to listen on.
- `--http-addr=roach1:8080` → DB Console UI address.
- `--join=roach1:26257,roach2:26257,roach3:26257,roach4:26257,roach5:26257` → list of all peer nodes. Same on every node.

**Start node 1 (this one publishes ports to your host):**

```bash
podman run -d \
  --name=roach1 \
  --hostname=roach1 \
  --net=roachnet \
  -p 26257:26257 -p 8080:8080 \
  -v roach1-data:/cockroach/cockroach-data \
  cockroachdb/cockroach:latest start \
    --insecure \
    --listen-addr=roach1:26257 \
    --http-addr=roach1:8080 \
    --join=roach1:26257,roach2:26257,roach3:26257,roach4:26257,roach5:26257
```

**Start node 2:**

```bash
podman run -d \
  --name=roach2 \
  --hostname=roach2 \
  --net=roachnet \
  -v roach2-data:/cockroach/cockroach-data \
  cockroachdb/cockroach:latest start \
    --insecure \
    --listen-addr=roach2:26257 \
    --http-addr=roach2:8080 \
    --join=roach1:26257,roach2:26257,roach3:26257,roach4:26257,roach5:26257
```

**Start node 3:**

```bash
podman run -d \
  --name=roach3 \
  --hostname=roach3 \
  --net=roachnet \
  -v roach3-data:/cockroach/cockroach-data \
  cockroachdb/cockroach:latest start \
    --insecure \
    --listen-addr=roach3:26257 \
    --http-addr=roach3:8080 \
    --join=roach1:26257,roach2:26257,roach3:26257,roach4:26257,roach5:26257
```

**Start node 4:**

```bash
podman run -d \
  --name=roach4 \
  --hostname=roach4 \
  --net=roachnet \
  -v roach4-data:/cockroach/cockroach-data \
  cockroachdb/cockroach:latest start \
    --insecure \
    --listen-addr=roach4:26257 \
    --http-addr=roach4:8080 \
    --join=roach1:26257,roach2:26257,roach3:26257,roach4:26257,roach5:26257
```

**Start node 5:**

```bash
podman run -d \
  --name=roach5 \
  --hostname=roach5 \
  --net=roachnet \
  -v roach5-data:/cockroach/cockroach-data \
  cockroachdb/cockroach:latest start \
    --insecure \
    --listen-addr=roach5:26257 \
    --http-addr=roach5:8080 \
    --join=roach1:26257,roach2:26257,roach3:26257,roach4:26257,roach5:26257
```

Confirm all 5 are running:

```bash
podman ps
```

At this point the nodes are running but the cluster is **not yet initialized**. If you check logs you'll see lines like *"node waiting for cluster initialization"* — that's expected.

```bash
podman logs roach1 | tail -20
```

---

## Step 6 — Initialize the cluster

This is run **once**. It tells the nodes to form a cluster.

```bash
podman exec -it roach1 ./cockroach init --insecure --host=roach1:26257
```

Expected output: `Cluster successfully initialized`.

Now check logs again — you'll see node IDs assigned, Raft groups forming, and the nodes becoming healthy.

```bash
podman logs roach1 | tail -30
```

---

## Step 7 — Open the DB Console (UI)

Open your browser to:

```
http://localhost:8080
```

Because we published roach1's `8080` to your host's `8080`, you reach the cluster through node 1. The UI works identically regardless of which node you connect to. You should see:

- **Cluster Overview** → 5 live nodes
- **Node List** → roach1 through roach5, all healthy
- **Metrics** → graphs starting to populate
- **Databases** → the system databases

If you want to reach the UI on the other nodes too, you'd need to publish their `8080` ports on different host ports (e.g. `-p 8081:8080` on roach2). Skipped here because one entry point is enough.

---

## Step 8 — Connect a SQL shell and run something

```bash
podman exec -it roach1 ./cockroach sql --insecure --host=roach1:26257
```

You're now in the CockroachDB SQL shell. Try:

```sql
CREATE DATABASE bank;
USE bank;
CREATE TABLE accounts (id INT PRIMARY KEY, balance DECIMAL);
INSERT INTO accounts VALUES (1, 1000.50), (2, 250.00);
SELECT * FROM accounts;
```

Now connect through a *different* node and verify the data is there (proving replication works):

```bash
podman exec -it roach3 ./cockroach sql --insecure --host=roach3:26257 \
  -e "SELECT * FROM bank.accounts;"
```

Same data, different node. That's the distributed SQL working.

Exit the SQL shell with `\q`.

---

## Step 9 — Raise the replication factor to 5

By default, CockroachDB replicates each range 3 times. With 5 nodes you can replicate 5 times so the cluster survives **2 simultaneous node failures** instead of just 1.

```bash
podman exec -it roach1 ./cockroach sql --insecure --host=roach1:26257
```

Then in the SQL shell:

```sql
ALTER RANGE default CONFIGURE ZONE USING num_replicas = 5;
ALTER RANGE meta CONFIGURE ZONE USING num_replicas = 5;
ALTER RANGE system CONFIGURE ZONE USING num_replicas = 5;
ALTER RANGE liveness CONFIGURE ZONE USING num_replicas = 5;
ALTER DATABASE system CONFIGURE ZONE USING num_replicas = 5;
```

Watch the **Replication** dashboard in the UI — you'll see ranges rebalancing as CockroachDB redistributes data to all 5 nodes.

---

## Step 10 — Test fault tolerance (optional but worth doing)

Stop one node and verify the cluster keeps working:

```bash
podman stop roach3
```

Open the DB Console — roach3 will appear as "Suspect", then "Dead" after ~5 minutes. Run a query through roach1 — it still works. Bring it back:

```bash
podman start roach3
```

It rejoins automatically. This is the magic of Raft consensus.

---

## Useful day-to-day commands

```bash
# View status of all nodes from the cluster's perspective
podman exec -it roach1 ./cockroach node status --insecure --host=roach1:26257

# Stop the whole cluster (data persists in volumes)
podman stop roach1 roach2 roach3 roach4 roach5

# Start it back up (no need to re-init)
podman start roach1 roach2 roach3 roach4 roach5

# Tail logs of a node
podman logs -f roach1

# Completely wipe and start over
podman stop roach1 roach2 roach3 roach4 roach5
podman rm roach1 roach2 roach3 roach4 roach5
podman volume rm roach1-data roach2-data roach3-data roach4-data roach5-data
podman network rm roachnet
```

---

## Common gotchas

The big one: **stop, then start** — never re-run `cockroach init`. Initializing twice is one of the most common mistakes. Also, if you're on a SELinux-enforcing system (RHEL/Fedora), volume mounts sometimes need `:Z` like `-v roach1-data:/cockroach/cockroach-data:Z`. And rootless Podman can occasionally have port-binding issues below 1024, but `26257` and `8080` are both fine. Finally, give the nodes 10–20 seconds after starting before running `init` — they need a moment to get on the network.

---

Once this is humming, since your interest is stocks/options with a database, a natural next step is creating a `market_data` database and modeling tables for option chains, OHLC bars, and trades — CockroachDB's strong consistency is genuinely useful for financial data. Want me to walk through a sensible schema for that as a follow-up?

### ScyllaDB vs Cassandra — Comparison & Podman Setup

Both are wide-column NoSQL databases speaking the same CQL protocol, but under the hood they're built very differently. Let me walk through the comparison first, then give you working Podman setups.

---

### Shared DNA

Both are direct descendants of Google Bigtable + Amazon Dynamo design papers. They share:

- **Data model**: Wide-column store (keyspaces → tables → partitions → rows → columns)
- **Query language**: CQL (Cassandra Query Language) — SQL-like syntax
- **Architecture**: Masterless (peer-to-peer), every node equal — no leader election like CockroachDB/YugabyteDB
- **Replication**: Configurable per keyspace via `replication_factor`
- **Consistency**: Tunable per query (ONE, QUORUM, ALL, LOCAL_QUORUM, etc.)
- **Topology**: Gossip protocol for cluster membership
- **Storage**: LSM-tree based (memtable → SSTable)
- **Compaction strategies**: STCS, LCS, TWCS — same names in both

This is why they're often discussed together — and why ScyllaDB markets itself as a "drop-in replacement" for Cassandra.

---

## Where They Diverge

### 1. Implementation Language

| | Cassandra | ScyllaDB |
|---|-----------|----------|
| Language | Java | C++ |
| Runtime | JVM (garbage collected) | Native binary, no GC |
| GC pauses | Yes — major operational concern | None |

This is the **single biggest difference**. Cassandra inherits all JVM characteristics: GC tuning, heap sizing, off-heap caches, occasional stop-the-world pauses. Scylla has none of that.

### 2. Threading Model

| | Cassandra | ScyllaDB |
|---|-----------|----------|
| Model | Thread-per-request, shared memory | **Shard-per-core (Seastar framework)** |
| Locking | Heavy synchronization | Lock-free per shard |
| Context switches | Many | Minimal |

Scylla pins one shard to each CPU core. Each shard owns its data exclusively — no locks, no shared state, no context switches. This is why Scylla can saturate modern hardware (32+ cores) while Cassandra struggles past 8-16 cores per node.

### 3. Performance (the headline numbers)

ScyllaDB consistently benchmarks **2-10× faster** than Cassandra for the same workload on the same hardware:

- Throughput: 1M+ ops/sec/node (Scylla) vs ~100-200K ops/sec/node (Cassandra)
- P99 latency: sub-millisecond (Scylla) vs 5-50ms (Cassandra)
- Per-node capacity: 100TB+ (Scylla) vs ~5TB practical limit (Cassandra)

This translates to **10× fewer nodes** for the same workload — the core value proposition Scylla pitches to enterprises.

### 4. Operational Differences

| Operation | Cassandra | ScyllaDB |
|-----------|-----------|----------|
| Startup time | 30-60s (JVM warmup) | <5s |
| Memory tuning | Constant heap/off-heap balancing | Self-tuning |
| Repair tool | `nodetool repair` (manual) | Auto-repair scheduler built-in |
| Compaction tuning | Manual | Mostly automatic |
| Backups | Manual snapshots + scripts | Manager (paid) or manual |
| Tombstones | Major operational pain point | Same data model issue, but better defaults |
| Admin tool | `nodetool` | `nodetool` (compatible) + `scylla` |

### 5. CQL Compatibility

Scylla aims for ~99% CQL compatibility with Cassandra. Differences:

- **User-Defined Functions (UDFs)** — Cassandra supports Java/JS, Scylla supports Lua/WASM
- **Materialized Views** — both support, but Scylla considers them experimental longer
- **Secondary indexes** — implementation differs internally
- **CDC (Change Data Capture)** — different formats, both work
- **Lightweight Transactions (LWT)** — Scylla's implementation differs (Raft-based in newer versions)

For 95% of application code, you can repoint your driver from Cassandra to Scylla and it just works.

### 6. Editions & Licensing

| | Cassandra | ScyllaDB |
|---|-----------|----------|
| OSS edition | Apache Cassandra (Apache 2.0) | ScyllaDB Open Source (was AGPL, now Source Available since 2024) |
| Enterprise | DataStax Enterprise (DSE) | ScyllaDB Enterprise (paid) |
| Cloud | DataStax Astra, AWS Keyspaces | ScyllaDB Cloud (managed) |
| License change | Stable | **Important: Scylla changed license in late 2024** — community/OSS edition was discontinued in favor of "Source Available" |

This license change matters: if your goal is permanent open-source, Cassandra is the safer long-term bet. If raw performance is the priority, Scylla is hard to beat.

### 7. When Each Wins

**Pick Cassandra when:**
- You need a guaranteed Apache-licensed open source database
- Your team has deep JVM expertise
- You're using a managed service (AWS Keyspaces, Astra)
- Ecosystem maturity matters (more drivers, tools, books, Stack Overflow answers)

**Pick ScyllaDB when:**
- Performance per node is critical (cost reduction)
- You want operational simplicity (less tuning)
- You're running at very large scale (100s of TB+)
- Latency-sensitive workloads (real-time bidding, fraud detection, gaming leaderboards)

### 8. Real-World Adopters

- **Cassandra**: Apple, Netflix (huge deployment), Instagram, eBay, Uber
- **ScyllaDB**: Discord (migrated from Cassandra), Comcast, Disney+, Samsung, Starbucks

Discord's 2023 migration story — moving trillions of messages from Cassandra to Scylla — is the most famous public migration case.

---

## Summary Table

| Aspect | Cassandra | ScyllaDB |
|--------|-----------|----------|
| Language | Java | C++ |
| Threading | Shared, locks | Shard-per-core, lock-free |
| GC pauses | Yes | None |
| Throughput/node | 100-200K ops/s | 1M+ ops/s |
| P99 latency | 5-50 ms | <1 ms |
| Startup | 30-60s | <5s |
| Memory tuning | Manual | Auto |
| Per-node capacity | ~5TB practical | 100TB+ |
| CQL compat | Native | ~99% compatible |
| License (OSS) | Apache 2.0 | Source Available (since 2024) |
| Production maturity | Highest (since 2008) | High (since 2015) |
| Operations difficulty | Higher | Lower |

---

# Podman Setup — Both Clusters in `venkat-net`

I'll give you 3-node clusters for each, on the same `venkat-net` network so you can compare side by side.

## Step 1: Create the network (if it doesn't exist)

```powershell
podman network ls
```

If `venkat-net` isn't there:

```powershell
podman network create venkat-net
```

## Step 2: Create persistent volumes

```powershell
# Cassandra
podman volume create cass1-data
podman volume create cass2-data
podman volume create cass3-data

# Scylla
podman volume create scylla1-data
podman volume create scylla2-data
podman volume create scylla3-data
```

---

## Cassandra 3-Node Cluster

### Start cass1 (the seed node)

```powershell
podman run -d --name cass1 --hostname cass1 --network venkat-net `
  -p 9042:9042 `
  -v cass1-data:/var/lib/cassandra `
  -e CASSANDRA_CLUSTER_NAME=venkat-cass `
  -e CASSANDRA_SEEDS=cass1 `
  -e CASSANDRA_DC=dc1 `
  -e CASSANDRA_RACK=rack1 `
  -e CASSANDRA_ENDPOINT_SNITCH=GossipingPropertyFileSnitch `
  -e MAX_HEAP_SIZE=512M `
  -e HEAP_NEWSIZE=128M `
  cassandra:5
```

Wait ~60 seconds for it to fully start — Cassandra is slow to boot.

```powershell
podman exec -it cass1 nodetool status
```

You should see one node `UN` (Up Normal) before continuing.

### Start cass2 and cass3

```powershell
podman run -d --name cass2 --hostname cass2 --network venkat-net `
  -v cass2-data:/var/lib/cassandra `
  -e CASSANDRA_CLUSTER_NAME=venkat-cass `
  -e CASSANDRA_SEEDS=cass1 `
  -e CASSANDRA_DC=dc1 `
  -e CASSANDRA_RACK=rack1 `
  -e CASSANDRA_ENDPOINT_SNITCH=GossipingPropertyFileSnitch `
  -e MAX_HEAP_SIZE=512M `
  -e HEAP_NEWSIZE=128M `
  cassandra:5
```

Wait ~60 seconds, then:

```powershell
podman run -d --name cass3 --hostname cass3 --network venkat-net `
  -v cass3-data:/var/lib/cassandra `
  -e CASSANDRA_CLUSTER_NAME=venkat-cass `
  -e CASSANDRA_SEEDS=cass1 `
  -e CASSANDRA_DC=dc1 `
  -e CASSANDRA_RACK=rack1 `
  -e CASSANDRA_ENDPOINT_SNITCH=GossipingPropertyFileSnitch `
  -e MAX_HEAP_SIZE=512M `
  -e HEAP_NEWSIZE=128M `
  cassandra:5
```

**Important:** Add Cassandra nodes **one at a time**, waiting for each to join before starting the next. Adding all three simultaneously causes split-brain issues.

### Verify Cassandra cluster

```powershell
podman exec -it cass1 nodetool status
```

Expected:
```
Datacenter: dc1
===============
Status=Up/Down |/ State=Normal/Leaving/Joining/Moving
--  Address    Load     Tokens  Owns  Host ID  Rack
UN  10.x.x.x   ...      256     ?     ...      rack1
UN  10.x.x.x   ...      256     ?     ...      rack1
UN  10.x.x.x   ...      256     ?     ...      rack1
```

### Connect with cqlsh

```powershell
podman exec -it cass1 cqlsh
```

Try a quick test:
```sql
CREATE KEYSPACE demo WITH replication = {'class': 'NetworkTopologyStrategy', 'dc1': 3};
USE demo;
CREATE TABLE users (id int PRIMARY KEY, name text);
INSERT INTO users (id, name) VALUES (1, 'venkat');
SELECT * FROM users;
EXIT;
```

---

## ScyllaDB 3-Node Cluster

### Start scylla1 (the seed)

```powershell
podman run -d --name scylla1 --hostname scylla1 --network venkat-net `
  -p 9043:9042 `
  -v scylla1-data:/var/lib/scylla `
  scylladb/scylla:latest `
  --seeds=scylla1 `
  --smp 1 `
  --memory 1G `
  --overprovisioned 1 `
  --cluster-name venkat-scylla `
  --endpoint-snitch GossipingPropertyFileSnitch
```

Note: I mapped Scylla's CQL port to **9043** on the host because Cassandra already grabbed 9042. Inside the network, both still use 9042.

Wait ~30 seconds:

```powershell
podman exec -it scylla1 nodetool status
```

### Start scylla2 and scylla3

```powershell
podman run -d --name scylla2 --hostname scylla2 --network venkat-net `
  -v scylla2-data:/var/lib/scylla `
  scylladb/scylla:latest `
  --seeds=scylla1 `
  --smp 1 `
  --memory 1G `
  --overprovisioned 1 `
  --cluster-name venkat-scylla `
  --endpoint-snitch GossipingPropertyFileSnitch
```

Wait ~30 seconds:

```powershell
podman run -d --name scylla3 --hostname scylla3 --network venkat-net `
  -v scylla3-data:/var/lib/scylla `
  scylladb/scylla:latest `
  --seeds=scylla1 `
  --smp 1 `
  --memory 1G `
  --overprovisioned 1 `
  --cluster-name venkat-scylla `
  --endpoint-snitch GossipingPropertyFileSnitch
```

### What those flags mean

| Flag | Purpose |
|------|---------|
| `--smp 1` | Use 1 CPU shard (Scylla wants 1 per core; limit for laptops) |
| `--memory 1G` | Cap memory at 1GB per node |
| `--overprovisioned 1` | Tell Scylla it's running on shared hardware (no CPU pinning) |
| `--seeds=scylla1` | Initial contact point for cluster join |

Without `--overprovisioned 1`, Scylla expects dedicated CPUs and will misbehave in a container.

### Verify Scylla cluster

```powershell
podman exec -it scylla1 nodetool status
```

Same `UN` output format as Cassandra (they share `nodetool`).

### Connect with cqlsh

```powershell
podman exec -it scylla1 cqlsh
```

Run the same test queries — they work identically.

To connect from your Windows host:

```powershell
# From host using cqlsh inside the container
podman exec -it scylla1 cqlsh

# From host using a port (Scylla on 9043, Cassandra on 9042)
# You'd need cqlsh installed on Windows, or use any CQL-compatible client
```

---

## Verify Both Are Running

```powershell
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected: 6 new containers (cass1-3, scylla1-3) plus your existing CockroachDB and YugabyteDB ones.

```powershell
podman exec -it cass1 nodetool status
podman exec -it scylla1 nodetool status
```

Both should show 3 `UN` nodes.

---

## Resource Reality Check

This setup is **heavy**:

| Cluster | Containers | Min RAM | Min CPU |
|---------|-----------|---------|---------|
| Existing CockroachDB | 3 | ~3 GB | 3 cores |
| Existing YugabyteDB | 3 | ~4 GB | 3 cores |
| New Cassandra | 3 | ~3 GB | 3 cores |
| New ScyllaDB | 3 | ~3 GB | 3 cores |
| **Total** | **12** | **~13 GB** | **~12 cores** |

If your machine has less than 16 GB RAM, **stop the CockroachDB or YugabyteDB cluster first** before starting these:

```powershell
# Stop everything CockroachDB
podman stop roach1 roach2 roach3

# Or stop YugabyteDB
podman stop yb1 yb2 yb3
```

You can restart them later with `podman start`.

---

## Practice Ideas

Once both are up, try the same operations on each and compare:

1. **Insert 100K rows** in both — compare wall time
2. **Kill one node** — `podman stop cass2` and `podman stop scylla2` — verify reads still work with `CONSISTENCY QUORUM`
3. **Check repair** — `nodetool repair` on Cassandra vs Scylla's auto-repair
4. **Decommission a node** — `nodetool decommission` works the same on both
5. **Add a 4th node** — practice scale-out
6. **Compare startup time** — restart cass1 vs scylla1, watch how much faster Scylla boots

Want me to walk through any of these specific scenarios? Or set up monitoring (Prometheus + Grafana) on `venkat-net` to actually see the performance difference visually?

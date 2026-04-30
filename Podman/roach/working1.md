Excellent question — you're poking at exactly the right thing to understand how CockroachDB is organized internally. Let me explain what's happening and give you a mental model that maps to PostgreSQL/MySQL.

---

## Why your queries failed — the new restriction

You hit a recent CockroachDB security change. The error message tells the whole story:

```
ERROR: Access to crdb_internal and system is restricted.
HINT: ... set the session variable allow_unsafe_internals = true
```

In recent CockroachDB versions, `crdb_internal` and `system` schemas are **locked down by default**, even for the `root` user. The reason: these tables expose internal implementation details that change between versions, and Cockroach Labs doesn't want apps depending on them.

To unlock them for your session (you're learning, this is fine):

```sql
SET allow_unsafe_internals = true;
```

This setting only lasts for your current SQL session. Open a new shell, you'll need to set it again.

---

## Mapping CockroachDB's structure to PostgreSQL/MySQL

Every database has metadata about itself — tables that describe tables, info about users, configurations, runtime stats. Each engine organizes it differently. Here's the parallel:

| Concept | PostgreSQL | MySQL | CockroachDB |
|---|---|---|---|
| Standard SQL metadata | `information_schema` | `information_schema` | `information_schema` |
| Engine-specific catalog | `pg_catalog` (e.g. `pg_class`, `pg_stat_activity`) | `mysql.*` and `performance_schema` | `crdb_internal` |
| Internal/admin tables | Not really separated | `mysql` schema | `system` |

So:
- **`information_schema`** → portable across all SQL databases. Works in CockroachDB, Postgres, MySQL — same query runs everywhere.
- **`crdb_internal`** → CockroachDB's equivalent of `pg_catalog` or `performance_schema`. Has cluster-specific stuff: nodes, ranges, gossip, jobs, contention events.
- **`system`** → the actual internal bookkeeping tables CockroachDB uses to run itself (users, settings, leases, descriptors). Closest analog: MySQL's `mysql` schema or Postgres's internal `pg_*` system tables.

---

## Now your specific query corrections

You tried several queries. Here's what works in current CockroachDB:

**First, unlock internal access:**

```sql
SET allow_unsafe_internals = true;
```

**See all nodes in the cluster (the modern way):**

```sql
SELECT node_id, address, sql_address, is_live, ranges, leases
FROM crdb_internal.kv_node_status;
```

That table is `kv_node_status`, not `node_status` (renamed in a recent version) and not `cluster_nodes`. Compare to:
- Postgres: `SELECT * FROM pg_stat_replication;`
- MySQL: `SHOW REPLICA STATUS;`

**See gossip/node info:**

```sql
SELECT node_id, address FROM crdb_internal.gossip_nodes;
```

This now works after `SET allow_unsafe_internals = true`.

**The simplest portable way — works without unlocking anything:**

```sql
SHOW NODES FROM CLUSTER;
```

Wait — actually CockroachDB removed `SHOW CLUSTER NODES`. The current syntax is just to use the system table directly, or check via the DB Console UI at `http://localhost:8080` which is far easier.

---

## Useful queries to learn cluster internals

After running `SET allow_unsafe_internals = true;`, try these — each one teaches you something about distributed databases:

**1. Which nodes exist and are healthy:**

```sql
SELECT node_id, address, is_live, started_at FROM crdb_internal.kv_node_status;
```

Postgres analog: `SELECT * FROM pg_stat_replication;` — but Postgres has one primary plus replicas. CockroachDB has 5 peers, all equal.

**2. How is data sliced into ranges:**

```sql
SELECT range_id, start_pretty, end_pretty, replicas, lease_holder
FROM crdb_internal.ranges
LIMIT 10;
```

This is *uniquely* CockroachDB. Your data is automatically split into ~512 MiB chunks called **ranges**, and each range is replicated to 3 (or 5, after your earlier setting) nodes. The `lease_holder` is the node currently authoritative for writes on that range. Postgres/MySQL have nothing like this — they have one primary.

**3. Currently running queries across the whole cluster:**

```sql
SELECT node_id, query, start FROM crdb_internal.cluster_queries;
```

- Postgres: `SELECT * FROM pg_stat_activity;` (one node)
- MySQL: `SHOW PROCESSLIST;` (one node)
- CockroachDB: aggregates across **all 5 nodes** automatically.

**4. Background jobs (schema changes, backups, etc.):**

```sql
SELECT job_id, job_type, status, created FROM crdb_internal.jobs LIMIT 10;
```

No direct analog — schema changes in Postgres/MySQL block your session, in CockroachDB they run as async distributed jobs.

**5. Cluster settings (these are tunables):**

```sql
SELECT variable, value FROM crdb_internal.cluster_settings WHERE value != '' LIMIT 20;
```

Postgres analog: `SHOW ALL;` or `SELECT * FROM pg_settings;`

**6. Portable query that works everywhere — list your tables:**

```sql
SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema='public';
```

Same query works on Postgres and MySQL.

---

## A mental model that should stick

Picture three concentric layers:

1. **Outermost — `information_schema`**: standard SQL metadata. Portable. Use this in application code so you can swap databases later.
2. **Middle — `crdb_internal`**: CockroachDB's view into its own behavior. Use this for ops, monitoring, debugging. Volatile across versions, hence the new restriction.
3. **Innermost — `system`**: the actual tables CockroachDB uses to run itself. You normally never touch these directly; you go through SQL commands like `CREATE USER`, `SET CLUSTER SETTING`, etc., which write to them on your behalf.

In Postgres, layer 2 is `pg_catalog` and layer 3 is also `pg_catalog` — they're not separated. In MySQL, layer 2 is `performance_schema` and layer 3 is the `mysql` schema.

---

## Why CockroachDB needs more internal tables than Postgres/MySQL

This is the real insight worth remembering:

A single-node Postgres knows about: its own connections, its own queries, its own tables. Roughly *N* internal concepts.

A 5-node CockroachDB cluster knows about: connections on every node, queries running cluster-wide, ranges (distributed shards) and where their replicas live, leaseholders, gossip messages between nodes, replication health, distributed jobs, contention events across nodes, time-travel snapshots. Roughly *N × 5 + distributed coordination metadata* internal concepts.

That's why `crdb_internal` is so much bigger than `pg_catalog`. The distributed nature of the database creates entirely new categories of metadata that single-node databases simply don't need.

---

## Try this right now

Run these in order in your roach4 SQL shell:

```sql
SET allow_unsafe_internals = true;
SELECT node_id, address, is_live FROM crdb_internal.kv_node_status;
SELECT count(*) FROM crdb_internal.ranges;
SELECT range_id, replicas, lease_holder FROM crdb_internal.ranges LIMIT 5;
```

The last query is the magical one — it shows you literally how your `bank.accounts` table is split and replicated across the 5 nodes. Look at the `replicas` array (e.g. `{1,3,5}`) — those are the node IDs holding copies of that range. That's the Raft consensus group in action.

Tell me what `SELECT range_id, replicas, lease_holder FROM crdb_internal.ranges LIMIT 5;` returns and I'll explain exactly what it means.

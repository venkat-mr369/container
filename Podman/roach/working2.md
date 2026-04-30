Good progress — you successfully ran one query and learned two things from the errors. Let me explain what happened and give you working alternatives.

---

## What worked and what it tells you

The `gossip_nodes` query worked beautifully. Look at the result:

```
node_id |   address
--------+---------------
   1    | roach1:26257
   2    | roach3:26257   ← interesting!
   3    | roach4:26257
   4    | roach5:26257
   5    | roach2:26257
```

Notice that the **node_id doesn't match the container name**. CockroachDB assigns node IDs in the order nodes *first joined the cluster*, not based on hostname. So `roach3` got `node_id=2` because it happened to register with the cluster before `roach2` did. This is normal — node IDs are CockroachDB's internal identifier; container hostnames are just what you named them in Podman.

Lesson: **always reference nodes by `node_id` in SQL queries**, and by hostname/container name when using Podman commands. They are two separate naming systems.

---

## Why the other two queries failed

**`column "sql_address" does not exist`** — I gave you a column that doesn't exist in your version. Schemas in `crdb_internal` change between versions, which is exactly why Cockroach Labs locked them down. The right move is always: discover columns first, then query.

**`SHOW NODES FROM CLUSTER` syntax error** — that syntax is invalid. There's no clean `SHOW NODES` statement in current CockroachDB; you have to query the internal tables.

---

## How to discover columns yourself (this is the real skill)

When a column doesn't exist, ask the database what columns DO exist. This is a portable SQL pattern that works in Postgres, MySQL, and CockroachDB:

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'crdb_internal'
  AND table_name = 'kv_node_status'
ORDER BY ordinal_position;
```

This is the same trick you'd use in Postgres to inspect any table — `information_schema.columns` is part of the SQL standard. Run this and you'll see exactly what columns `kv_node_status` has in your version.

Compare to:
- Postgres: `\d crdb_internal.kv_node_status` in psql, or the same `information_schema.columns` query.
- MySQL: `DESCRIBE crdb_internal.kv_node_status;` or `SHOW COLUMNS FROM ...`.

CockroachDB also supports the `SHOW COLUMNS` syntax:

```sql
SHOW COLUMNS FROM crdb_internal.kv_node_status;
```

Try that — easier to type.

---

## A safer query that should just work

Here's a query using only columns that have been stable for many CockroachDB versions:

```sql
SELECT node_id, address, started_at, is_live
FROM crdb_internal.kv_node_status;
```

If `is_live` also fails, drop it:

```sql
SELECT node_id, address, started_at
FROM crdb_internal.kv_node_status;
```

To get liveness info specifically, there's a separate table:

```sql
SELECT node_id, epoch, expiration, draining, membership
FROM crdb_internal.kv_node_liveness;
```

This pattern — splitting status from liveness into separate tables — exists because in a distributed system, "is the node alive" is a different question (with a different update frequency and source of truth) than "what's the node's metadata." Postgres doesn't need this distinction because there's only one primary; everything is local.

---

## The cleanest cluster-wide overview query

Try this — it joins gossip info (which works for you) with liveness:

```sql
SELECT
  g.node_id,
  g.address,
  l.epoch,
  l.expiration,
  l.draining,
  l.membership
FROM crdb_internal.gossip_nodes g
LEFT JOIN crdb_internal.kv_node_liveness l
  ON g.node_id = l.node_id
ORDER BY g.node_id;
```

What each column means:

- **`epoch`** — increments every time the node restarts. Roughly: "how many times has this node come back to life." Distributed databases need this to detect zombie nodes claiming to hold leases they no longer own.
- **`expiration`** — when this node's "I'm alive" heartbeat expires. Nodes have to renew this every few seconds. If they fail to, the cluster declares them dead.
- **`draining`** — true when a node is shutting down gracefully (handing off its leases before exit).
- **`membership`** — `active`, `decommissioning`, or `decommissioned`. This is how you permanently retire a node.

None of these concepts exist in single-node Postgres or MySQL. They all stem from one fact: **multiple machines have to agree on who's alive**.

---

## Now try the ranges query — this is the cool one

Whether or not the above works, run this:

```sql
SHOW COLUMNS FROM crdb_internal.ranges;
```

Then:

```sql
SELECT range_id, start_pretty, end_pretty, replicas, lease_holder
FROM crdb_internal.ranges
LIMIT 10;
```

If a column doesn't exist, the error message tells you, and you know to check `SHOW COLUMNS` first. That feedback loop — query, error, inspect schema, fix query — is exactly how working DBAs use unfamiliar databases.

---

## Big takeaways from this session

First: when working with `crdb_internal`, the schema is not part of the public SQL contract. Always inspect with `SHOW COLUMNS` or `information_schema.columns` before assuming a column exists. This is true for `pg_catalog` in Postgres too, just less often a problem because Postgres evolves more slowly.

Second: CockroachDB's metadata is split into many small focused tables (`gossip_nodes`, `kv_node_status`, `kv_node_liveness`, `ranges`, `leases`...) because it has to track concepts that don't exist in single-node databases — gossip, liveness epochs, range replicas, leaseholders. Each table has one job. Postgres tends to have fewer, fatter catalog tables.

Third: node IDs are not hostnames. Your `roach3` is `node_id=2`. Internalize this now and it'll save you confusion later.

Run the `SHOW COLUMNS FROM crdb_internal.kv_node_status;` query and paste the output — I'll help you build a proper status query from the actual columns your version exposes.

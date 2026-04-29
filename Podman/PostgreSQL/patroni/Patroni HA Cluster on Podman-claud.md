### Patroni HA Cluster on Podman — PostgreSQL 16 Step-by-Step Learning Guide

A learner-friendly walkthrough to build a real PostgreSQL 16 high-availability cluster using only Podman containers. Every step explains **what**, **why**, and **how to verify**. At the end you'll create a sample stock/options schema and test automatic failover.

---

## What we are building (Architecture)

```
                           +-------------------+
        Apps connect ----> |   HAProxy         |  ports: 5000 (writes), 5001 (reads), 7000 (stats)
                           +---------+---------+
                                     |
              +----------------------+----------------------+
              |                      |                      |
        +-----v-----+          +-----v-----+          +-----v-----+
        |  pg-node1 |          |  pg-node2 |          |  pg-node3 |
        |  Patroni  |          |  Patroni  |          |  Patroni  |
        |  PG 16    |          |  PG 16    |          |  PG 16    |
        +-----+-----+          +-----+-----+          +-----+-----+
              |                      |                      |
              +----------+-----------+----------+-----------+
                         |                      
                   +-----v------+               
                   |   etcd     |   <-- Distributed Configuration Store (DCS)
                   +------------+               
```

| Component | Role |
|---|---|
| **etcd** | Stores cluster state. Decides who is the primary. Patroni's "brain". |
| **Patroni** | Python agent next to PostgreSQL. Talks to etcd, manages PG, handles failover. |
| **PostgreSQL 16** | The actual database. One primary, two replicas (streaming replication). |
| **HAProxy** | Single entry point. Routes write traffic to primary, read traffic to replicas. |

**Note on production vs learning:** In production etcd should be 3 or 5 nodes. We'll use 1 etcd node here to keep the learning curve smaller. Everything else (3 PG nodes) reflects real production patterns.

---

## Prerequisites

```bash
# Check podman is installed and working
podman --version
podman info | head -20
```

You should see Podman 4.x or 5.x. If not installed: `sudo apt install podman` (Debian/Ubuntu) or `sudo dnf install podman` (Fedora/RHEL).

---

# PHASE 1 — Network and Volumes

## Step 1.1 — Create a dedicated network

**Why:** Containers on the same Podman network can find each other by container name (built-in DNS). Without this, you'd need IPs and that breaks on restart.

```bash
podman network create patroni-net
```

**Verify:**
```bash
podman network ls
podman network inspect patroni-net
```

You should see `patroni-net` listed.

## Step 1.2 — Create persistent volumes

**Why:** Containers are throw-away. Volumes keep data alive when a container restarts or is recreated. Each PG node gets its own volume — they each store their own copy of the data.

```bash
podman volume create etcd-data
podman volume create pg-node1-data
podman volume create pg-node2-data
podman volume create pg-node3-data
```

**Verify:**
```bash
podman volume ls
```

You should see all four volumes.

---

# PHASE 2 — etcd (the DCS)

etcd is the source of truth for "who is the primary right now". Patroni writes a key here every few seconds. If the primary's key expires, the replicas race to take over.

## Step 2.1 — Run the etcd container

```bash
podman run -d \
  --name etcd \
  --network patroni-net \
  --hostname etcd \
  -v etcd-data:/etcd-data \
  -e ETCD_NAME=etcd \
  -e ETCD_DATA_DIR=/etcd-data \
  -e ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379 \
  -e ETCD_ADVERTISE_CLIENT_URLS=http://etcd:2379 \
  -e ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380 \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd:2380 \
  -e ETCD_INITIAL_CLUSTER=etcd=http://etcd:2380 \
  -e ETCD_INITIAL_CLUSTER_TOKEN=patroni-etcd-token \
  -e ETCD_INITIAL_CLUSTER_STATE=new \
  -e ETCD_ENABLE_V2=false \
  quay.io/coreos/etcd:v3.5.15
```

**Understand each flag:**
- `-d` — detached (runs in background)
- `--network patroni-net` — joins our network
- `--hostname etcd` — name other containers will use to reach it
- `-v etcd-data:/etcd-data` — mount the volume so data survives restarts
- `ETCD_LISTEN_CLIENT_URLS` — listen on all interfaces inside the container
- `ETCD_ADVERTISE_CLIENT_URLS` — what address other containers should use to talk to it
- `ETCD_INITIAL_CLUSTER_STATE=new` — bootstrapping a fresh cluster

## Step 2.2 — Verify etcd is healthy

```bash
podman logs etcd | tail -20

# Run an etcdctl command inside the container
podman exec etcd etcdctl endpoint health
podman exec etcd etcdctl endpoint status -w table
```

You should see `is healthy: successfully committed proposal`. If not, check the logs.

---

# PHASE 3 — Build the Patroni + PostgreSQL 16 Image

There's no official Patroni image for PG 16 from Postgres themselves, so we build our own from the official `postgres:16` image.

## Step 3.1 — Create the build context folder

```bash
mkdir -p ~/patroni-build
cd ~/patroni-build
```

## Step 3.2 — Create a Containerfile

Save this as `~/patroni-build/Containerfile`:

```dockerfile
FROM docker.io/library/postgres:16

USER root

# Install Python and tools needed by Patroni
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        curl \
        ca-certificates \
        less \
        vim \
    && rm -rf /var/lib/apt/lists/*

# Install Patroni in an isolated virtualenv (avoids conflicts with system python)
RUN python3 -m venv /opt/patroni \
    && /opt/patroni/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/patroni/bin/pip install --no-cache-dir \
        "patroni[etcd3]" \
        psycopg2-binary

# Make patroni and patronictl available on PATH
ENV PATH="/opt/patroni/bin:${PATH}"

# Folders Patroni and PG will use
RUN mkdir -p /etc/patroni /home/postgres/pgdata \
    && chown -R postgres:postgres /etc/patroni /home/postgres \
    && chmod 700 /home/postgres/pgdata

# PG 16 binaries are at /usr/lib/postgresql/16/bin in the official image
ENV PATH="/usr/lib/postgresql/16/bin:${PATH}"

USER postgres
WORKDIR /home/postgres

EXPOSE 5432 8008

ENTRYPOINT ["patroni"]
CMD ["/etc/patroni/patroni.yml"]
```

**What this does:**
1. Starts from the official PG 16 image (so all PG binaries are already there).
2. Installs Python venv tools.
3. Creates a venv at `/opt/patroni` and installs Patroni + the etcd3 client + psycopg2 (PG driver).
4. Creates `/etc/patroni` (config) and `/home/postgres/pgdata` (data) folders.
5. Switches to the `postgres` user (Patroni must not run as root).
6. The entrypoint just runs `patroni /etc/patroni/patroni.yml`.

## Step 3.3 — Build the image

```bash
cd ~/patroni-build
podman build -t patroni-pg16:local .
```

This will take a couple of minutes the first time. **Verify:**

```bash
podman images | grep patroni-pg16
```

---

# PHASE 4 — Configure and Start Patroni Nodes

Each node needs its **own** YAML config file. The only differences between nodes are `name` and `connect_address`.

## Step 4.1 — Create a config folder on the host

```bash
mkdir -p ~/patroni-configs
```

## Step 4.2 — Create the config for node 1

Save as `~/patroni-configs/node1.yml`:

```yaml
scope: stockcluster                # cluster name (any name you like)
namespace: /service/                # path prefix in etcd
name: pg-node1                      # unique per node

restapi:
  listen: 0.0.0.0:8008
  connect_address: pg-node1:8008    # how others reach this node's REST API

etcd3:
  hosts: etcd:2379                  # using container DNS name

bootstrap:
  # These DCS settings are only written to etcd at first cluster init.
  # Later changes must go through `patronictl edit-config`.
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 200
        shared_buffers: 256MB
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 256MB
        max_wal_senders: 10
        max_replication_slots: 10
        checkpoint_timeout: 15min
        archive_mode: "off"

  initdb:
    - encoding: UTF8
    - data-checksums
    - locale: C.UTF-8

  pg_hba:
    - host replication replicator 0.0.0.0/0 md5
    - host all all 0.0.0.0/0 md5

  users:
    admin:
      password: admin
      options:
        - createrole
        - createdb

postgresql:
  listen: 0.0.0.0:5432
  connect_address: pg-node1:5432
  data_dir: /home/postgres/pgdata/data
  bin_dir: /usr/lib/postgresql/16/bin
  pgpass: /tmp/pgpass0
  authentication:
    replication:
      username: replicator
      password: replpass
    superuser:
      username: postgres
      password: postgres
    rewind:
      username: rewind_user
      password: rewindpass
  parameters:
    unix_socket_directories: '/var/run/postgresql,/tmp'

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
```

## Step 4.3 — Create configs for node 2 and node 3

Easiest: copy node1.yml and change two lines (`name` and `connect_address` lines).

```bash
cp ~/patroni-configs/node1.yml ~/patroni-configs/node2.yml
cp ~/patroni-configs/node1.yml ~/patroni-configs/node3.yml

sed -i 's/pg-node1/pg-node2/g' ~/patroni-configs/node2.yml
sed -i 's/pg-node1/pg-node3/g' ~/patroni-configs/node3.yml
```

**Verify:**
```bash
grep -E '^name:|connect_address:' ~/patroni-configs/node*.yml
```

You should see `pg-node1`, `pg-node2`, `pg-node3` for each respective file.

## Step 4.4 — Start node 1 (this becomes primary)

```bash
podman run -d \
  --name pg-node1 \
  --network patroni-net \
  --hostname pg-node1 \
  -v pg-node1-data:/home/postgres/pgdata \
  -v ~/patroni-configs/node1.yml:/etc/patroni/patroni.yml:Z \
  patroni-pg16:local
```

**Flag notes:**
- `:Z` on the bind mount handles SELinux relabeling on RHEL/Fedora. On Debian/Ubuntu it's harmless — leave it in.

**Watch it bootstrap (this is fascinating to read the first time):**

```bash
podman logs -f pg-node1
```

You should see lines like:
- `INFO: trying to bootstrap a new cluster`
- `INFO: running post_bootstrap`
- `INFO: initialized a new cluster`
- `INFO: no action. I am (pg-node1), the leader with the lock`

Press Ctrl+C to stop following logs.

## Step 4.5 — Start node 2 (becomes a replica)

```bash
podman run -d \
  --name pg-node2 \
  --network patroni-net \
  --hostname pg-node2 \
  -v pg-node2-data:/home/postgres/pgdata \
  -v ~/patroni-configs/node2.yml:/etc/patroni/patroni.yml:Z \
  patroni-pg16:local
```

```bash
podman logs -f pg-node2
```

Look for:
- `INFO: bootstrap from leader 'pg-node1'`
- `INFO: replica has been created using basebackup_fast_xlog`
- `INFO: no action. I am (pg-node2), a secondary, and following a leader (pg-node1)`

## Step 4.6 — Start node 3

```bash
podman run -d \
  --name pg-node3 \
  --network patroni-net \
  --hostname pg-node3 \
  -v pg-node3-data:/home/postgres/pgdata \
  -v ~/patroni-configs/node3.yml:/etc/patroni/patroni.yml:Z \
  patroni-pg16:local
```

```bash
podman logs pg-node3 | tail -20
```

## Step 4.7 — See the cluster state

```bash
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml list
```

Expected output:

```
+ Cluster: stockcluster (xxxxxxxxxxxxxxxxxxx) -----+----+-----------+
| Member   | Host          | Role    | State     | TL | Lag in MB |
+----------+---------------+---------+-----------+----+-----------+
| pg-node1 | pg-node1:5432 | Leader  | running   |  1 |           |
| pg-node2 | pg-node2:5432 | Replica | streaming |  1 |         0 |
| pg-node3 | pg-node3:5432 | Replica | streaming |  1 |         0 |
+----------+---------------+---------+-----------+----+-----------+
```

If you see this — **congratulations, your HA cluster is alive**.

---

# PHASE 5 — HAProxy (Single Entry Point)

Apps shouldn't need to know which node is primary. HAProxy queries each Patroni REST API and routes traffic accordingly.

## Step 5.1 — Create the HAProxy config

```bash
mkdir -p ~/haproxy-config
```

Save as `~/haproxy-config/haproxy.cfg`:

```
global
    maxconn 200

defaults
    log     global
    mode    tcp
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s

# HAProxy stats web UI on port 7000
listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /
    stats refresh 5s

# Writes go here (port 5000) — only the primary answers HTTP 200 on /primary
listen primary
    bind *:5000
    option httpchk GET /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg-node1 pg-node1:5432 maxconn 100 check port 8008
    server pg-node2 pg-node2:5432 maxconn 100 check port 8008
    server pg-node3 pg-node3:5432 maxconn 100 check port 8008

# Read-only traffic goes here (port 5001) — replicas answer HTTP 200 on /replica
listen replicas
    bind *:5001
    option httpchk GET /replica
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    balance roundrobin
    server pg-node1 pg-node1:5432 maxconn 100 check port 8008
    server pg-node2 pg-node2:5432 maxconn 100 check port 8008
    server pg-node3 pg-node3:5432 maxconn 100 check port 8008
```

**Key idea:** Patroni's REST API returns:
- HTTP 200 on `/primary` only if that node is currently the leader.
- HTTP 200 on `/replica` only if it's a healthy streaming replica.

So HAProxy automatically follows the cluster as failovers happen.

## Step 5.2 — Run HAProxy

```bash
podman run -d \
  --name haproxy \
  --network patroni-net \
  -p 5000:5000 \
  -p 5001:5001 \
  -p 7000:7000 \
  -v ~/haproxy-config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro,Z \
  docker.io/library/haproxy:2.9
```

**Verify:**

Open in browser: `http://localhost:7000/`

You'll see a stats page. Under the **primary** section, exactly one server should be green. Under **replicas**, the other two should be green.

---

# PHASE 6 — Connect and Verify

## Step 6.1 — Connect to the primary via HAProxy

From the host (you may need `psql` installed: `sudo apt install postgresql-client`):

```bash
PGPASSWORD=postgres psql -h localhost -p 5000 -U postgres -d postgres
```

Or run psql inside one of the containers:

```bash
podman exec -it pg-node1 psql -h haproxy -p 5000 -U postgres -d postgres
# Password: postgres
```

## Step 6.2 — Run sanity SQL

```sql
-- Confirm version
SELECT version();

-- Am I primary or replica?
SELECT pg_is_in_recovery();   -- should be 'f' (false) on primary

-- See replication status (run on primary)
SELECT client_addr, state, sync_state, write_lag, replay_lag
FROM pg_stat_replication;
```

You should see two rows in `pg_stat_replication` — one for each replica.

## Step 6.3 — Connect to a read replica via HAProxy port 5001

```bash
PGPASSWORD=postgres psql -h localhost -p 5001 -U postgres -d postgres
```

```sql
SELECT pg_is_in_recovery();   -- should be 't' (true) on replica
```

---

# PHASE 7 — Stock Market Schema (Your Use Case)

Now the fun part. We'll create a schema for stocks, options, OHLC candles, and trades.

## Step 7.1 — Connect as superuser to the primary

```bash
PGPASSWORD=postgres psql -h localhost -p 5000 -U postgres -d postgres
```

## Step 7.2 — Create a database and dedicated user

```sql
CREATE DATABASE marketdata;
CREATE USER trader WITH PASSWORD 'TraderPass123';
GRANT ALL PRIVILEGES ON DATABASE marketdata TO trader;

\c marketdata trader
```

## Step 7.3 — Create the schema

```sql
-- Master list of all tradable instruments (stocks, futures, options)
CREATE TABLE instruments (
    instrument_id   BIGSERIAL PRIMARY KEY,
    symbol          VARCHAR(50)  NOT NULL,
    exchange        VARCHAR(20)  NOT NULL,        -- NSE, BSE, MCX
    instrument_type VARCHAR(10)  NOT NULL,        -- EQ, FUT, CE, PE
    underlying      VARCHAR(50),                  -- e.g. NIFTY, RELIANCE
    expiry_date     DATE,
    strike_price    NUMERIC(12,2),
    lot_size        INTEGER      NOT NULL DEFAULT 1,
    tick_size       NUMERIC(10,4) NOT NULL DEFAULT 0.05,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (exchange, symbol)
);

CREATE INDEX idx_instruments_underlying ON instruments(underlying);
CREATE INDEX idx_instruments_expiry ON instruments(expiry_date) WHERE is_active;

-- 1-minute OHLC candles
CREATE TABLE ohlc_minute (
    instrument_id BIGINT      NOT NULL REFERENCES instruments(instrument_id),
    candle_time   TIMESTAMPTZ NOT NULL,
    open_price    NUMERIC(14,4) NOT NULL,
    high_price    NUMERIC(14,4) NOT NULL,
    low_price     NUMERIC(14,4) NOT NULL,
    close_price   NUMERIC(14,4) NOT NULL,
    volume        BIGINT NOT NULL DEFAULT 0,
    open_interest BIGINT,                          -- only for derivatives
    PRIMARY KEY (instrument_id, candle_time)
);

CREATE INDEX idx_ohlc_minute_time ON ohlc_minute(candle_time DESC);

-- Strategies you trade
CREATE TABLE strategies (
    strategy_id   SERIAL PRIMARY KEY,
    name          VARCHAR(100) NOT NULL UNIQUE,
    description   TEXT,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Every order placed
CREATE TABLE orders (
    order_id       BIGSERIAL PRIMARY KEY,
    instrument_id  BIGINT      NOT NULL REFERENCES instruments(instrument_id),
    strategy_id    INTEGER     REFERENCES strategies(strategy_id),
    order_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    side           CHAR(1)     NOT NULL CHECK (side IN ('B','S')),  -- Buy / Sell
    order_type     VARCHAR(10) NOT NULL,          -- MARKET, LIMIT, SL, SL-M
    quantity       INTEGER     NOT NULL CHECK (quantity > 0),
    price          NUMERIC(14,4),
    status         VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    broker_order_id VARCHAR(64)
);

CREATE INDEX idx_orders_time ON orders(order_time DESC);
CREATE INDEX idx_orders_strategy ON orders(strategy_id, order_time DESC);

-- Executed trades (an order may produce one or more trades)
CREATE TABLE trades (
    trade_id       BIGSERIAL PRIMARY KEY,
    order_id       BIGINT      NOT NULL REFERENCES orders(order_id),
    instrument_id  BIGINT      NOT NULL REFERENCES instruments(instrument_id),
    trade_time     TIMESTAMPTZ NOT NULL,
    side           CHAR(1)     NOT NULL,
    quantity       INTEGER     NOT NULL,
    price          NUMERIC(14,4) NOT NULL,
    fees           NUMERIC(10,4) NOT NULL DEFAULT 0
);

-- Open positions (one row per (instrument, strategy) currently held)
CREATE TABLE positions (
    position_id   BIGSERIAL PRIMARY KEY,
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    strategy_id   INTEGER NOT NULL REFERENCES strategies(strategy_id),
    quantity      INTEGER NOT NULL,                 -- positive = long, negative = short
    avg_price     NUMERIC(14,4) NOT NULL,
    opened_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (instrument_id, strategy_id)
);
```

## Step 7.4 — Insert sample data

```sql
INSERT INTO instruments (symbol, exchange, instrument_type, underlying, lot_size) VALUES
  ('RELIANCE', 'NSE', 'EQ', 'RELIANCE', 1),
  ('TCS',      'NSE', 'EQ', 'TCS',      1),
  ('NIFTY',    'NSE', 'EQ', 'NIFTY',    1);

INSERT INTO instruments (symbol, exchange, instrument_type, underlying, expiry_date, strike_price, lot_size) VALUES
  ('NIFTY26MAY24500CE', 'NSE', 'CE', 'NIFTY', '2026-05-28', 24500.00, 75),
  ('NIFTY26MAY24500PE', 'NSE', 'PE', 'NIFTY', '2026-05-28', 24500.00, 75),
  ('NIFTY26MAY24600CE', 'NSE', 'CE', 'NIFTY', '2026-05-28', 24600.00, 75);

INSERT INTO strategies (name, description) VALUES
  ('IRON_CONDOR', 'Sell OTM CE + Sell OTM PE + Buy further OTM CE + Buy further OTM PE'),
  ('COVERED_CALL', 'Long stock + Short OTM call');

-- A sample buy order and trade
WITH new_order AS (
  INSERT INTO orders (instrument_id, strategy_id, side, order_type, quantity, price, status)
  SELECT instrument_id, 1, 'S', 'LIMIT', 75, 120.50, 'COMPLETE'
  FROM instruments WHERE symbol='NIFTY26MAY24500CE'
  RETURNING order_id, instrument_id
)
INSERT INTO trades (order_id, instrument_id, trade_time, side, quantity, price)
SELECT order_id, instrument_id, NOW(), 'S', 75, 120.50 FROM new_order;
```

## Step 7.5 — Verify replication is working

In a **second terminal**, connect to a replica via port 5001 and read the data:

```bash
PGPASSWORD=TraderPass123 psql -h localhost -p 5001 -U trader -d marketdata
```

```sql
SELECT symbol, instrument_type, strike_price FROM instruments;
SELECT * FROM orders;
```

You should see exactly the same data — replication is working in real time.

Try to write on the replica (it should fail):

```sql
INSERT INTO instruments(symbol, exchange, instrument_type) VALUES ('TEST','NSE','EQ');
-- ERROR: cannot execute INSERT in a read-only transaction
```

This is correct and expected. Replicas are read-only.

---

# PHASE 8 — Test Automatic Failover

This is the whole point of Patroni. Let's kill the primary and watch a replica take over.

## Step 8.1 — Identify current primary

```bash
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml list
```

Note which node has `Role: Leader` (probably `pg-node1`).

## Step 8.2 — Stop the primary container

```bash
podman stop pg-node1
```

## Step 8.3 — Watch a replica get promoted (within ~30 seconds)

```bash
# Wait a few seconds, then:
podman exec -it pg-node2 patronictl -c /etc/patroni/patroni.yml list
```

You'll see `pg-node1` gone, and either `pg-node2` or `pg-node3` is now `Leader`. The timeline (`TL`) increments to `2` on the new leader.

## Step 8.4 — Verify HAProxy routes you to the new primary

```bash
PGPASSWORD=postgres psql -h localhost -p 5000 -U postgres -d marketdata -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

`pg_is_in_recovery` should be `f` (false). The IP returned will be the new primary's.

Try a write — it works:

```sql
INSERT INTO strategies(name, description) VALUES ('STRADDLE_TEST','Failover test');
SELECT * FROM strategies;
```

## Step 8.5 — Bring back pg-node1 as a replica

```bash
podman start pg-node1
```

Watch logs — Patroni will detect a new leader exists and rejoin as a replica:

```bash
podman logs -f pg-node1
```

Look for: `INFO: Lock owner: pg-nodeX; I am pg-node1` and then `INFO: starting as a secondary`.

After a minute:

```bash
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml list
```

All three nodes should be back, with the **new** node still as Leader. `pg-node1` is now a Replica.

## Step 8.6 — Manual switchover (planned, for maintenance)

If you ever want to move the leader on purpose (e.g. for maintenance on the current leader):

```bash
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml switchover
```

Follow the prompts. This is graceful — no data loss.

---

# PHASE 9 — Useful Patroni Operations

```bash
# Cluster status (use any container — they all see the same etcd)
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml list

# Edit cluster-wide PG parameters (writes to etcd)
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml edit-config

# Show current effective config from etcd
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml show-config

# Restart a single node (rolling restart pattern)
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml restart stockcluster pg-node2

# Pause Patroni (lets you do manual PG ops without Patroni interfering)
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml pause
podman exec -it pg-node1 patronictl -c /etc/patroni/patroni.yml resume
```

---

# Cleanup

When you want to delete everything and start fresh:

```bash
# Stop and remove containers
podman stop haproxy pg-node1 pg-node2 pg-node3 etcd
podman rm   haproxy pg-node1 pg-node2 pg-node3 etcd

# Remove volumes (THIS DELETES ALL DATA)
podman volume rm etcd-data pg-node1-data pg-node2-data pg-node3-data

# Remove network
podman network rm patroni-net

# Optional: remove the image
podman rmi patroni-pg16:local
```

---

# Troubleshooting Cheat Sheet

| Symptom | Likely cause | Fix |
|---|---|---|
| `pg-node2` log: `connection to server ... failed` | Node 1 not ready yet | Wait 30s, restart node 2: `podman restart pg-node2` |
| `patronictl list` shows nothing | etcd unreachable | `podman logs etcd` and confirm it's healthy |
| HAProxy stats page shows all servers DOWN | Patroni REST API not on 8008 | Check `restapi.listen` in YAML, check `podman logs pg-node1` |
| `data directory ... has invalid permissions` | Volume permissions | `podman exec -u root pg-node1 chown -R postgres:postgres /home/postgres/pgdata && chmod 700 /home/postgres/pgdata/data` |
| Replicas not catching up | Replication slot full / WAL too small | Increase `wal_keep_size` in `patronictl edit-config` |
| `pg_is_in_recovery()` returns `t` on port 5000 | HAProxy still routing to old primary | Check Patroni REST: `curl http://localhost:8008/primary` from inside the network |

---

# What to learn next (in order)

1. **3-node etcd cluster** — replace the single etcd with a real 3-node cluster.
2. **WAL-G / pgBackRest** — backup and PITR (point-in-time recovery).
3. **Synchronous replication** — set `synchronous_mode: true` in Patroni for zero-data-loss failover.
4. **TimescaleDB extension** — perfect for OHLC time-series data; install on top of PG 16.
5. **Connection pooling** — add PgBouncer between HAProxy and PG for high connection counts.
6. **TLS** — encrypt etcd-to-Patroni and client-to-PG traffic.

---

**You now have a working PostgreSQL 16 HA cluster on Podman.** Each step you ran taught you one piece: networking, DCS, image building, Patroni config, replication, load balancing, schema design, and failover. Practice the failover (Phase 8) several times — that's where the magic of Patroni really lands.

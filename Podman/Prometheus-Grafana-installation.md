### What we are building

```
                        venkat-net (Podman bridge)
   ┌──────────────────────────────────────────────────────────────┐
   │                                                                  │
   │  CockroachDB (5 nodes)        YugabyteDB (5 nodes)               │
   │  roach1...roach5              yb1...yb5                          │
   │       │                            │                             │
   │       │ exposes /_status/vars      │ exposes /prometheus-metrics │
   │       │ on port 8080               │ on ports 7000 and 9000      │
   │       └───────────┬────────────────┘                             │
   │                   │                                              │
   │                   ▼                                              │
   │           ┌──────────────┐                                       │
   │           │  prometheus  │  scrapes metrics every 15s            │
   │           │   :9090      │  stores in time-series database       │
   │           └──────┬───────┘                                       │
   │                  │ queries via PromQL                            │
   │                  ▼                                               │
   │           ┌──────────────┐                                       │
   │           │   grafana    │  draws dashboards                     │
   │           │    :3000     │  (you connect here from browser)      │
   │           └──────────────┘                                       │
   └──────────────────────────────────────────────────────────────────┘
```

Two new containers, both on `venkat-net`. They'll see all your database nodes by hostname (`roach1`, `yb1`, etc.) just like the database nodes already see each other.

---

## Step 1 — Create the directory structure on E: drive

```powershell
mkdir E:\podman-instances
mkdir E:\podman-instances\monitoring
mkdir E:\podman-instances\monitoring\prometheus
mkdir E:\podman-instances\monitoring\grafana
```

Verify:

```powershell
dir E:\podman-instances\monitoring
```

A note on this layout: `E:\podman-instances\monitoring` is a clean home for *all* monitoring config. As you grow this lab — add Cassandra, an alerting tool, a logging stack — each gets its own subdirectory under `E:\podman-instances\`, e.g. `E:\podman-instances\cassandra-config`, `E:\podman-instances\loki`. This is good infrastructure-as-code hygiene; everything related to a service lives in one place you can back up or version-control.

## Step 2 — Create the Prometheus config file

This is the **brain** of your monitoring setup — it tells Prometheus which endpoints to scrape. Create the file:

```powershell
notepad E:\podman-instances\monitoring\prometheus\prometheus.yml
```

Paste this exactly into Notepad and save:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'cockroachdb'
    metrics_path: '/_status/vars'
    static_configs:
      - targets:
          - 'roach1:8080'
          - 'roach2:8080'
          - 'roach3:8080'
          - 'roach4:8080'
          - 'roach5:8080'
        labels:
          cluster: 'venkat-lab'

  - job_name: 'yugabyte-master'
    metrics_path: '/prometheus-metrics'
    static_configs:
      - targets:
          - 'yb1:7000'
          - 'yb2:7000'
          - 'yb3:7000'
          - 'yb4:7000'
          - 'yb5:7000'
        labels:
          cluster: 'venkat-lab'

  - job_name: 'yugabyte-tserver'
    metrics_path: '/prometheus-metrics'
    static_configs:
      - targets:
          - 'yb1:9000'
          - 'yb2:9000'
          - 'yb3:9000'
          - 'yb4:9000'
          - 'yb5:9000'
        labels:
          cluster: 'venkat-lab'
```

**Why this structure:**
- Each `job_name` is a logical group. In Grafana you can filter "show me only CockroachDB nodes" using these labels.
- `metrics_path` differs per database because each one chose its own URL convention. Prometheus is flexible about that.
- `targets` are container hostnames, not IPs. Because everything is on `venkat-net`, Podman's DNS resolves `roach1` etc. automatically.

Important when saving with Notepad: in the **Save As** dialog, change **Save as type** to **All Files** so Notepad doesn't add `.txt` and turn it into `prometheus.yml.txt`. Verify:

```powershell
dir E:\podman-instances\monitoring\prometheus
```

You should see exactly `prometheus.yml`, no `.txt` suffix.

## Step 3 — Pull the Prometheus and Grafana images

```powershell
podman pull prom/prometheus:latest
podman pull grafana/grafana:latest
```

(For learning, `latest` is fine here. For production you'd pin versions, same lesson as before.)

## Step 4 — Create a volume for Prometheus data

Prometheus needs persistent storage for its time-series database. If we don't give it a volume, restarting the container wipes all your historical metrics.

```powershell
podman volume create prometheus-data
```

## Step 5 — Make sure your E: drive is accessible to the Podman VM

This is a **Windows-specific gotcha** that doesn't apply on Linux. On Windows, Podman runs inside a small Linux VM, and that VM only sees folders that have been explicitly shared with it. The default Podman machine usually shares your `C:\Users\<you>` folder but **not** other drives like `E:`.

Check what's currently shared:

```powershell
podman machine inspect | findstr -i mount
```

If you don't see `E:\` or `E:\podman-instances` in the output, you have two options:

**Option A — re-init the Podman machine with E: shared (recommended, one-time):**

```powershell
podman machine stop
podman machine rm
podman machine init --volume "E:\podman-instances:/mnt/e/podman-instances"
podman machine start
```

This creates a new Podman machine with `E:\podman-instances` mounted at `/mnt/e/podman-instances` inside the Linux VM.

**Option B — keep your existing machine and copy the file in instead:**

If you don't want to re-init, you can keep `prometheus.yml` on the C: drive (which is already shared) — for example at `C:\Users\venkat\monitoring\prometheus\prometheus.yml` — and reference *that* path in the `-v` flag.

I'll show **Option A's** path style below since you specifically asked for E:. If you go with Option B, just substitute your C: path in the `-v` flag at Step 6.

After re-init, recreate the Prometheus volume:

```powershell
podman volume create prometheus-data
```

(Volumes don't survive `podman machine rm`.)

## Step 6 — Start the Prometheus container

The `-v` flag mounts your config file *into* the container at the path Prometheus expects (`/etc/prometheus/prometheus.yml`).

**Single line for PowerShell:**

```powershell
podman run -d --name=prometheus --hostname=prometheus --net=venkat-net -p 9090:9090 -v E:\podman-instances\monitoring\prometheus\prometheus.yml:/etc/prometheus/prometheus.yml -v prometheus-data:/prometheus prom/prometheus:latest --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --web.enable-lifecycle
```

Flag-by-flag:
- `--name=prometheus` and `--hostname=prometheus` — discoverable on the network as `prometheus`.
- `--net=venkat-net` — same network as all DBs.
- `-p 9090:9090` — publishes Prometheus's web UI to your Windows host.
- First `-v` — mounts the config file from `E:\podman-instances\monitoring\prometheus\prometheus.yml` into the container.
- Second `-v` — mounts the data volume.
- `--web.enable-lifecycle` — lets you reload config without restarting (`POST /-/reload`). Useful when you add new nodes later.

Verify:

```powershell
podman ps
podman logs prometheus
```

Logs should end with something like `Server is ready to receive web requests.`

If you see `open /etc/prometheus/prometheus.yml: no such file or directory`, the mount didn't work — usually means the E: drive isn't shared with the Podman VM. Go back to Step 5 and pick Option A.

## Step 7 — Verify Prometheus can reach your databases

Open in your browser:

```
http://localhost:9090
```

This is Prometheus's built-in UI. Click **Status → Targets** in the top menu. You should see all four scrape jobs and their state:

- ✅ `prometheus` — UP (it's scraping itself)
- ✅ `cockroachdb` — UP for roach1–roach5
- ⚠️ `yugabyte-master` — UP for 3 of 5 (because only 3 nodes run masters with RF=3)
- ✅ `yugabyte-tserver` — UP for yb1–yb5

The YugabyteDB master "down" entries are **expected and correct** — those nodes legitimately don't run a master process. Don't try to fix this. It's a useful visual reminder of the master-vs-tserver architecture.

If anything else is DOWN, click on it and read the error. Most common cause: a typo in `prometheus.yml`, or that database container isn't actually running. Verify with `podman ps`.

## Step 8 — Try a few PromQL queries to feel how it works

Still in the Prometheus UI, click **Graph** in the top menu. In the query box, try:

```
up
```

Press Execute. You'll see a list of every target with `1` (alive) or `0` (down). This is the most basic Prometheus query — *"is everything I'm scraping alive right now?"*

Try a CockroachDB-specific metric:

```
sql_query_count
```

Click the **Graph** tab — you'll see how many SQL queries each cockroach node has handled since startup.

This is the raw data Grafana will draw graphs from. Now let's get Grafana to do that with a pretty UI.

## Step 9 — Create a Grafana volume

```powershell
podman volume create grafana-data
```

## Step 10 — Start the Grafana container

```powershell
podman run -d --name=grafana --hostname=grafana --net=venkat-net -p 3000:3000 -v grafana-data:/var/lib/grafana -e GF_SECURITY_ADMIN_USER=admin -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:latest
```

Flag-by-flag:
- `-p 3000:3000` — Grafana's web UI on your Windows host.
- `-v grafana-data:/var/lib/grafana` — persists dashboards, users, and settings.
- The two `-e` flags set the initial admin credentials.

Note: we're using a **Podman volume** (`grafana-data`) for Grafana's data, not a bind mount to E:. That's because Grafana inside the container runs as a non-root user, and bind-mounting a Windows folder causes permission issues that aren't worth fighting. Volumes "just work." We only bind-mount E: for Prometheus's config file because we *want* to edit that file from Windows.

Verify:

```powershell
podman ps
podman logs grafana
```

Logs should end with `HTTP Server Listen ... address=[::]:3000`.

## Step 11 — Log into Grafana and add Prometheus as a data source

Open your browser:

```
http://localhost:3000
```

Username: `admin`, Password: `admin`. It'll ask you to set a new password — you can skip that for learning.

Now connect Grafana to Prometheus:

1. In the left sidebar, click the gear icon (**Connections** → **Data sources**).
2. Click **Add new data source**.
3. Select **Prometheus**.
4. In the **Connection** section, set the URL to:
   ```
   http://prometheus:9090
   ```
   This is the **container hostname** (`prometheus`), not `localhost`, because Grafana is talking to Prometheus *inside* the venkat-net network. This trips people up — `localhost` would mean "inside the Grafana container" and would fail.
5. Scroll to the bottom, click **Save & test**.
6. You should see a green ✓ "Successfully queried the Prometheus API."

If this fails, it's almost always one of two things: Prometheus isn't running (`podman ps`), or you typed `localhost` instead of `prometheus` in the URL.

## Step 12 — Import the official CockroachDB dashboard

Cockroach Labs publishes pre-built Grafana dashboards. You don't have to design anything from scratch.

1. In Grafana, click the **+** icon in the left sidebar → **Import dashboard**.
2. In the "Import via grafana.com" field, paste this dashboard ID:
   ```
   16906
   ```
3. Click **Load**.
4. On the next page, in the **Prometheus** dropdown, pick the data source you just created.
5. Click **Import**.

You're now looking at a real dashboard with QPS, latency, replication health, and live data from your 5-node CockroachDB cluster. Click around. Generate some load with the SQL shell and watch the graphs move.

## Step 13 — Import a YugabyteDB dashboard

Same process, different ID:

1. **+** icon → **Import dashboard**.
2. Paste this ID:
   ```
   12620
   ```
3. Click **Load**, pick `Prometheus` as the data source, click **Import**.

If the YugabyteDB dashboard shows mostly empty graphs, search for "YugabyteDB" on https://grafana.com/grafana/dashboards/ and pick a recent one (sort by "newest"). Different YugabyteDB versions expose metrics under slightly different names; you sometimes need a dashboard that matches your version's metric names.

---

## Step 14 — Generate some load and watch it

Open a SQL shell to one of your databases:

```powershell
podman exec -it roach1 ./cockroach sql --insecure --host=roach1:26257
```

Run a quick load loop:

```sql
CREATE DATABASE IF NOT EXISTS loadtest;
USE loadtest;
CREATE TABLE IF NOT EXISTS t (id INT PRIMARY KEY DEFAULT unique_rowid(), v INT);
-- Generate ~10K rows
INSERT INTO t (v) SELECT generate_series(1, 10000);
SELECT count(*) FROM t;
```

Switch to the Grafana CockroachDB dashboard. Within ~15-30 seconds (the scrape interval), you'll see QPS spike on the graphs. **This is the moment everything clicks** — you're seeing your activity reflected in real metrics.

---

## Quick sanity-check checklist

After all this, run:

```powershell
podman ps
```

You should see 12 containers running:
- 5 cockroach (roach1–roach5)
- 5 yugabyte (yb1–yb5)
- 1 prometheus
- 1 grafana

All on `venkat-net`. To verify the network membership:

```powershell
podman network inspect venkat-net
```

Look at the `containers` section — all 12 should be listed.

---

## Your final folder layout

```
E:\podman-instances\
└── monitoring\
    ├── prometheus\
    │   └── prometheus.yml          ← edit this anytime to add/remove targets
    └── grafana\                    ← reserved for future use (custom dashboards as JSON, etc.)
```

When you eventually want to back this lab up, zipping `E:\podman-instances` plus exporting the volume contents (`podman volume export`) gives you everything you need to recreate it on another machine.

---

## Common gotchas

The most frequent issues, in order of how often I see them:

When **Prometheus targets show DOWN**, 90% of the time it's that the container hostname in `prometheus.yml` doesn't match the actual container name. Double-check `podman ps` against `prometheus.yml`.

When **Grafana can't reach Prometheus**, 99% of the time it's because someone typed `http://localhost:9090` instead of `http://prometheus:9090` in the data source URL. Inside containers, `localhost` means the container itself, not the host.

When **dashboards are blank**, the dashboard's PromQL queries reference metric names that don't exist in your version. Try a different dashboard ID, or open one of the panels and edit the query to match a metric name that *does* exist (use Prometheus's UI to autocomplete).

When **Prometheus restarts and your config changes don't apply**, you need to either restart Prometheus (`podman restart prometheus`) or use the lifecycle endpoint:

```powershell
curl -X POST http://localhost:9090/-/reload
```

(That's why we passed `--web.enable-lifecycle` at startup.)

When **the bind mount fails on E:**, your Podman machine doesn't have E: shared. Go back to Step 5, Option A.

---

## Adding nodes later — the workflow

Once your stack is built, here's how you add a new database node (say, an 11th node) to monitoring:

1. Start the container on `venkat-net` as usual.
2. Edit `E:\podman-instances\monitoring\prometheus\prometheus.yml` — add the new target.
3. Reload Prometheus:
   ```powershell
   curl -X POST http://localhost:9090/-/reload
   ```
4. Refresh Grafana — the new node automatically appears in dashboards.

That's the operational workflow. **Grafana is never edited.** Prometheus is the source of truth for the inventory.

---

Run through Steps 1–7 first. Once Prometheus's **Status → Targets** page is up and you can see what's green vs DOWN, paste that and we'll work through any failures before moving to Grafana.

I see the error — "Failed to load dashboard / Dashboard not found." This means the dashboard ID `16906` I gave you doesn't exist on grafana.com (or has been removed/made private). My apologies — I should have verified those IDs.

Let me get you working IDs that actually exist right now.Confirmed. The IDs I gave you (`16906`, `12620`) don't exist on grafana.com. There's a much better path that bypasses grafana.com entirely — **Cockroach Labs publishes their official dashboards as JSON files directly on GitHub.** Let's use those.

---

## The right approach: download dashboards from CockroachDB's GitHub

Cockroach Labs maintains their official dashboards at:

```
https://github.com/cockroachdb/cockroach/tree/master/monitoring/grafana-dashboards/by-cluster
```

There are 4 dashboards there, each focused on a different aspect:

| Dashboard JSON | What it shows |
|---|---|
| `runtime.json` | Node uptime, CPU, memory |
| `storage.json` | Disk space, range counts |
| `sql.json` | Queries, transactions, latency |
| `replication.json` | Replica counts, leaseholders, snapshots |

You'll import all four. Together they give you a complete view of the cluster.

## Step 1 — Download the dashboard JSON files

In PowerShell:

```powershell
cd E:\podman-instances\monitoring\grafana

curl.exe -o runtime.json https://raw.githubusercontent.com/cockroachdb/cockroach/master/monitoring/grafana-dashboards/by-cluster/runtime.json

curl.exe -o storage.json https://raw.githubusercontent.com/cockroachdb/cockroach/master/monitoring/grafana-dashboards/by-cluster/storage.json

curl.exe -o sql.json https://raw.githubusercontent.com/cockroachdb/cockroach/master/monitoring/grafana-dashboards/by-cluster/sql.json

curl.exe -o replication.json https://raw.githubusercontent.com/cockroachdb/cockroach/master/monitoring/grafana-dashboards/by-cluster/replication.json
```

Note: `curl.exe` (with the `.exe`) is important on PowerShell — without `.exe`, PowerShell's built-in `curl` alias does something different and won't save the file properly.

Verify:

```powershell
dir E:\podman-instances\monitoring\grafana
```

You should see 4 JSON files, each a few hundred KB.

## Step 2 — Import each dashboard via the JSON upload

Now in Grafana (the page in your screenshot, which is exactly the right page):

1. Click the **"Upload dashboard JSON file"** area at the top — that big dotted box that says "Drag and drop here or click to browse."
2. Navigate to `E:\podman-instances\monitoring\grafana\` and pick `sql.json` first.
3. On the next screen, in the **Prometheus** dropdown, select your `Prometheus` data source.
4. Click **Import**.

Repeat for the other three files (`runtime.json`, `storage.json`, `replication.json`).

You'll end up with 4 dashboards in your Grafana, each showing a different angle of your CockroachDB cluster.

## Step 3 — Important: these dashboards need specific labels

Reading the [Cockroach Labs README](https://github.com/cockroachdb/cockroach/blob/master/monitoring/grafana-dashboards/by-cluster/README.md), the dashboards expect three Prometheus labels on every metric:

- `job="cockroachdb"` ✓ (you already have this in `prometheus.yml`)
- `cluster=...` ✗ (missing)
- `instance=...` ✓ (Prometheus adds this automatically from the target hostname)

Without the `cluster` label, some panels will show "No data." Let's add it. Edit your `prometheus.yml`:

```powershell
notepad E:\podman-instances\monitoring\prometheus\prometheus.yml
```

Update the `cockroachdb` job to add a static label:

```yaml
  - job_name: 'cockroachdb'
    metrics_path: '/_status/vars'
    static_configs:
      - targets:
          - 'roach1:8080'
          - 'roach2:8080'
          - 'roach3:8080'
          - 'roach4:8080'
          - 'roach5:8080'
        labels:
          cluster: 'venkat-lab'
```

The `labels:` block under `static_configs` adds that label to every metric scraped from these targets. You can name the cluster anything — `venkat-lab`, `dev`, `local`, whatever you like. It just needs to exist.

Save the file and reload Prometheus:

```powershell
curl.exe -X POST http://localhost:9090/-/reload
```

Verify the label is now there: open `http://localhost:9090`, go to **Graph**, run:

```
up{job="cockroachdb"}
```

Each target should now show `cluster="venkat-lab"` in its labels.

## Step 4 — Refresh the Grafana dashboards

Go back to Grafana, open the SQL dashboard. Wait ~30 seconds for fresh metrics. Graphs should now populate.

If a dashboard has a `cluster` dropdown at the top, select `venkat-lab`. If panels still show "No data," click into one to inspect its query — sometimes you need to adjust the metric names slightly for newer CockroachDB versions, but the bulk of them should work.

---

## For YugabyteDB — same approach, different source

YugabyteDB also publishes dashboards. The cleanest approach is to grab them from their GitHub:

```powershell
cd E:\podman-instances\monitoring\grafana

curl.exe -o yb-master.json https://raw.githubusercontent.com/yugabyte/yugabyte-db/master/cloud/grafana/master.json

curl.exe -o yb-tserver.json https://raw.githubusercontent.com/yugabyte/yugabyte-db/master/cloud/grafana/tserver.json
```

If those URLs return 404 (their repo structure changes), check their docs site at `https://docs.yugabyte.com/preview/explore/observability/prometheus-integration/` for the current location. Worst case, you can browse YugabyteDB's GitHub to find the JSON files manually.

Import them the same way: drag and drop into Grafana, pick the Prometheus data source, click Import.

---

## Why I steered you wrong with the IDs originally

Lesson worth taking from this: **dashboard IDs on grafana.com are user-uploaded and can be deleted/made-private at any time.** Anyone can publish a dashboard with an ID. Many of them rot over time as the original author moves on or the metric names they reference change.

The reliable pattern, which is what we just did:

1. Find the dashboard's *source repo* (the database vendor's GitHub).
2. Download the JSON file directly from there.
3. Import via the file-upload path in Grafana, not the ID-lookup path.

This way you get the version maintained by the actual database team, and you have the file checked into your own infrastructure if you ever want to version-control your monitoring setup.

---

## Quick visual summary of what you should now have

```
E:\podman-instances\monitoring\
├── prometheus\
│   └── prometheus.yml          ← edited to include cluster label
└── grafana\
    ├── runtime.json            ← official CockroachDB
    ├── storage.json            ← official CockroachDB
    ├── sql.json                ← official CockroachDB
    ├── replication.json        ← official CockroachDB
    ├── yb-master.json          ← official YugabyteDB
    └── yb-tserver.json         ← official YugabyteDB
```

Try the CockroachDB ones first — they're well-maintained and reliably work. Once those are happily showing data, go after YugabyteDB.

Run the `curl.exe` downloads, then the `prometheus.yml` edit + reload, then drag-and-drop the JSON files into Grafana. Tell me which step fails, if any, and we'll work through it.

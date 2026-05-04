### Complete Decommission Steps 

**Goal:** Remove containers `roach4` and `roach5` from your 5-node cluster, leaving 3 nodes (`roach1`, `roach2`, `roach3`).

**Container → Node ID mapping** (from your earlier `node status` output):

| Container | Node ID |
|-----------|---------|
| roach1 | 1 |
| roach2 | 3 |
| roach3 | 4 |
| **roach4** | **5** ← to remove |
| **roach5** | **2** ← to remove |

---

## Step 1: Lower 5-replica zones to 3

Required because your `system` database and critical ranges are configured for 5 replicas. Without this, decommission will hang.

```powershell
podman exec -it roach1 ./cockroach sql --insecure --host=roach1:26257 -e "ALTER RANGE meta CONFIGURE ZONE USING num_replicas = 3; ALTER RANGE system CONFIGURE ZONE USING num_replicas = 3; ALTER RANGE liveness CONFIGURE ZONE USING num_replicas = 3; ALTER DATABASE system CONFIGURE ZONE USING num_replicas = 3;"
```

## Step 2: Verify zone changes

```powershell
podman exec -it roach1 ./cockroach sql --insecure --host=roach1:26257 -e "SHOW ALL ZONE CONFIGURATIONS;" | Select-String "num_replicas"
```

All values should show `num_replicas = 3`.

## Step 3: Wait for cluster to be healthy

```powershell
podman exec -it roach1 ./cockroach node status --ranges --insecure --host=roach1:26257
```

Wait until `ranges_underreplicated = 0` for every node.

## Step 4: Decommission node ID 5 (container roach4)

```powershell
podman exec -it roach1 ./cockroach node decommission 5 --insecure --host=roach1:26257
```

Watch the streaming output. Wait until you see `replicas = 0` and `decommissioning = true`. Do not press Ctrl+C.

## Step 5: Stop container roach4

```powershell
podman stop roach4
```

## Step 6: Decommission node ID 2 (container roach5)

```powershell
podman exec -it roach1 ./cockroach node decommission 2 --insecure --host=roach1:26257
```

Again, wait for `replicas = 0`.

## Step 7: Stop container roach5

```powershell
podman stop roach5
```

## Step 8: Verify final cluster state

```powershell
podman exec -it roach1 ./cockroach node status --decommission --insecure --host=roach1:26257
```

Expected:
- Nodes 1, 3, 4 → `is_live = true`, `membership = active`
- Nodes 5, 2 → `membership = decommissioned`

## Step 9: Remove the containers

```powershell
podman rm roach4 roach5
```

## Step 10 (optional): Remove their data volumes

```powershell
podman volume ls
podman volume rm podman volume rm roach4-data roach5-data
```

---

## Quick reference — what each command does

| Command | Purpose |
|---------|---------|
| `ALTER ... num_replicas = 3` | Tell cluster to keep only 3 copies of system data |
| `node decommission <id>` | Move all data off a node, then mark it retired |
| `podman stop <container>` | Stop the container after CockroachDB has drained it |
| `podman rm <container>` | Delete the stopped container |

---

## Final reminders

After this, you have **3 nodes with replication factor 3** — losing any one node will halt the cluster. Fine for learning, not for production.

Decommissioned node IDs (2 and 5) are **permanently retired** — if you add nodes later, they'll get fresh IDs (6, 7, ...).

Run Step 1 first and share the output before moving to Step 4. Good luck!

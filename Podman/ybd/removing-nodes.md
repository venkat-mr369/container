### Remove yb4 and yb5 nodes

**Setup confirmed:**
- yb4 and yb5 are tserver-only (not masters) → simpler removal
- RF is already 3 → no zone changes needed
- Masters live on yb1, yb2, yb3

---

## Step 1: Blacklist yb4 and yb5

```powershell
podman exec -it yb1 /home/yugabyte/bin/yb-admin --master_addresses yb1:7100,yb2:7100,yb3:7100 change_blacklist ADD yb4:9100 yb5:9100
```

## Step 2: Watch data move off (run repeatedly)

```powershell
podman exec -it yb1 /home/yugabyte/bin/yb-admin --master_addresses yb1:7100,yb2:7100,yb3:7100 get_load_move_completion
```

Wait until output shows `Percent complete = 100`.

## Step 3: Verify yb4 and yb5 are empty

```powershell
podman exec -it yb1 /home/yugabyte/bin/yb-admin --master_addresses yb1:7100,yb2:7100,yb3:7100 list_all_tablet_servers
```

yb4 and yb5 should show as `BLACKLISTED` with 0 tablets.

## Step 4: Stop the containers

```powershell
podman stop yb4 yb5
```

## Step 5: Verify final cluster

```powershell
podman exec -it yb1 /home/yugabyte/bin/yb-admin --master_addresses yb1:7100,yb2:7100,yb3:7100 list_all_tablet_servers
```

Only yb1, yb2, yb3 should be `ALIVE`.

## Step 6: Remove containers

```powershell
podman rm yb4 yb5
```

## Step 7 (optional): Clean blacklist

```powershell
podman exec -it yb1 /home/yugabyte/bin/yb-admin --master_addresses yb1:7100,yb2:7100,yb3:7100 change_blacklist REMOVE yb4:9100 yb5:9100
```
## Remove Volume
```bash
podman volume rm yb4-data yb5-data
```

---

## Quick reference

| Step | What it does |
|------|--------------|
| 1 | Tell cluster to drain data off yb4 and yb5 |
| 2 | Monitor until drain finishes |
| 3 | Confirm nodes are empty |
| 4 | Stop the now-empty containers |
| 5 | Confirm cluster is healthy with 3 nodes |
| 6 | Delete the stopped containers |
| 7 | Tidy up blacklist entries |


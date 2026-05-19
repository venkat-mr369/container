### Create Podman Network

```bash
podman network create venkat-net
```

If already created, ignore the error.

---

### Create MariaDB Volumes

```bash
podman volume create mariadb1-data
podman volume create mariadb2-data
podman volume create mariadb3-data
podman volume create maxscale-data
```

---

### Verify Volumes

```bash
podman volume ls
```

Expected:

```text
local       mariadb1-data
local       mariadb2-data
local       mariadb3-data
local       maxscale-data
```

---

### Pull Images

```bash
podman pull docker.io/mariadb:11.4
podman pull docker.io/mariadb/maxscale:24.02
```

---

### Start Galera Bootstrap Node (mariadb1)

```bash
podman run -d \
--name mariadb1 \
--hostname mariadb1 \
--network venkat-net \
-p 3306:3306 \
-p 4567:4567 \
-p 4568:4568 \
-p 4444:4444 \
-v mariadb1-data:/var/lib/mysql:Z \
-e MARIADB_ROOT_PASSWORD='Maria@123' \
-e MARIADB_GALERA_CLUSTER_NAME='galera_cluster' \
-e MARIADB_GALERA_CLUSTER_ADDRESS='gcomm://' \
-e MARIADB_GALERA_MARIABACKUP_PASSWORD='backup123' \
-e MARIADB_GALERA_NODE_ADDRESS='mariadb1' \
-e MARIADB_GALERA_NODE_NAME='galera1' \
docker.io/mariadb:11.4
```

---

### Check mariadb1 Logs

```bash
podman logs -f mariadb1
```

Wait until you see something similar to:

```text
WSREP: Server status change synced -> joined
```

Press:

```bash
CTRL + C
```

---

### Start mariadb2

```bash
podman run -d \
--name mariadb2 \
--hostname mariadb2 \
--network venkat-net \
-v mariadb2-data:/var/lib/mysql:Z \
-e MARIADB_ROOT_PASSWORD='Maria@123' \
-e MARIADB_GALERA_CLUSTER_NAME='galera_cluster' \
-e MARIADB_GALERA_CLUSTER_ADDRESS='gcomm://mariadb1' \
-e MARIADB_GALERA_MARIABACKUP_PASSWORD='backup123' \
-e MARIADB_GALERA_NODE_ADDRESS='mariadb2' \
-e MARIADB_GALERA_NODE_NAME='galera2' \
docker.io/mariadb:11.4
```

---

### Start mariadb3

```bash
podman run -d \
--name mariadb3 \
--hostname mariadb3 \
--network venkat-net \
-v mariadb3-data:/var/lib/mysql:Z \
-e MARIADB_ROOT_PASSWORD='Maria@123' \
-e MARIADB_GALERA_CLUSTER_NAME='galera_cluster' \
-e MARIADB_GALERA_CLUSTER_ADDRESS='gcomm://mariadb1' \
-e MARIADB_GALERA_MARIABACKUP_PASSWORD='backup123' \
-e MARIADB_GALERA_NODE_ADDRESS='mariadb3' \
-e MARIADB_GALERA_NODE_NAME='galera3' \
docker.io/mariadb:11.4
```

---

### Verify Running Containers

```bash
podman ps
```

Expected:

```text
mariadb1
mariadb2
mariadb3
```

---

### Verify Galera Cluster

Connect:

```bash
podman exec -it mariadb1 mysql -uroot -p
```

Password:

```text
MariaDB@123
```

Run:

```sql
SHOW STATUS LIKE 'wsrep_cluster_size';
```

Expected:

```text
3
```

---

### Create MaxScale User

Inside MariaDB:

```sql
CREATE USER 'maxuser'@'%' IDENTIFIED BY 'maxpwd';

GRANT ALL PRIVILEGES ON *.* TO 'maxuser'@'%';

FLUSH PRIVILEGES;
```

Exit:

```sql
exit
```

---

### Create MaxScale Config Directory

```bash
mkdir -p ~/maxscale
```

---

### Create MaxScale Configuration File

```bash
vi ~/maxscale/maxscale.cnf
```

Paste:

```ini
[maxscale]
threads=auto

[server1]
type=server
address=mariadb1
port=3306
protocol=MariaDBBackend

[server2]
type=server
address=mariadb2
port=3306
protocol=MariaDBBackend

[server3]
type=server
address=mariadb3
port=3306
protocol=MariaDBBackend

[Galera-Monitor]
type=monitor
module=galeramon
servers=server1,server2,server3
user=maxuser
password=maxpwd
monitor_interval=2s

[RW-Service]
type=service
router=readwritesplit
servers=server1,server2,server3
user=maxuser
password=maxpwd

[RW-Listener]
type=listener
service=RW-Service
protocol=MariaDBClient
port=3306
```

Save:

```bash
:wq
```

---

### Start MaxScale

```bash
podman run -d \
--name maxscale \
--hostname maxscale \
--network venkat-net \
-p 3307:3306 \
-v ~/maxscale/maxscale.cnf:/etc/maxscale.cnf:Z \
docker.io/mariadb/maxscale:24.02
```

---

### Verify MaxScale Logs

```bash
podman logs -f maxscale
```

Press:

```bash
CTRL + C
```

---

### Verify MaxScale Servers

```bash
podman exec -it maxscale maxctrl list servers
```

Expected:

* All 3 nodes should be Running
* One node should show Master

---

### Connect Through MaxScale

```bash
mysql -h 127.0.0.1 -P 3307 -u maxuser -p
```

Password:

```text
maxpwd
```

---

### Test Replication

Create database:

```sql
CREATE DATABASE venkatdb;
```

Now verify from another node:

```bash
podman exec -it mariadb2 mysql -uroot -p
```

Run:

```sql
SHOW DATABASES;
```

You should see:

```text
venkatdb
```

---

### Test Failover

Stop current primary:

```bash
podman stop mariadb1
```

Check MaxScale:

```bash
podman exec -it maxscale maxctrl list servers
```

Another node should become active automatically.

---

### Start Stopped Node Again

```bash
podman start mariadb1
```

---

### Check Cluster Status

```bash
podman exec -it mariadb1 mysql -uroot -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
```

---

### Stop Entire Environment

```bash
podman stop mariadb1 mariadb2 mariadb3 maxscale
```

---

### Start Entire Environment

Start bootstrap node first:

```bash
podman start mariadb1
```

Then:

```bash
podman start mariadb2 mariadb3 maxscale
```

---

### Remove Entire Environment

```bash
podman rm -f mariadb1 mariadb2 mariadb3 maxscale
```

```bash
podman volume rm mariadb1-data mariadb2-data mariadb3-data maxscale-data
```

---

### Architecture

```text
                +----------------------+
                |      MaxScale        |
                |      Port 3307       |
                +----------+-----------+
                           |
        -----------------------------------------
        |                  |                    |
+---------------+ +---------------+ +---------------+
|   mariadb1    | |   mariadb2    | |   mariadb3    |
|   Galera Node | |   Galera Node | |   Galera Node |
+---------------+ +---------------+ +---------------+
```

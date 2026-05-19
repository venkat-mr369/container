### Create Podman Network

```powershell
podman network create venkat-net
```

If already created, ignore the error.

---

### Create MariaDB Volumes

```powershell
podman volume create mariadb1-data
podman volume create mariadb2-data
podman volume create mariadb3-data
podman volume create maxscale-data
```

---

### Verify Volumes

```powershell
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

### Create Base Directory

```powershell
mkdir E:\podman-instances\mysql-mariadb
```

---

### Create MaxScale Config Directory

```powershell
mkdir E:\podman-instances\mysql-mariadb\maxscale
```

---

### Pull Images

```powershell
podman pull docker.io/mariadb:11.4
podman pull docker.io/mariadb/maxscale:24.02
```

---

### Start Bootstrap Node (mariadb1)

```powershell
podman run -d `
--name mariadb1 `
--hostname mariadb1 `
--network venkat-net `
-p 3306:3306 `
-p 4567:4567 `
-p 4568:4568 `
-p 4444:4444 `
-v mariadb1-data:/var/lib/mysql `
-e MARIADB_ROOT_PASSWORD="Maria@123" `
docker.io/mariadb:11.4 `
--wsrep_on=ON `
--wsrep_provider=/usr/lib/galera/libgalera_smm.so `
--wsrep_cluster_name=galera_cluster `
--wsrep_cluster_address=gcomm:// `
--wsrep_node_name=galera1 `
--wsrep_node_address=mariadb1 `
--binlog_format=ROW `
--default-storage-engine=InnoDB `
--innodb_autoinc_lock_mode=2 `
--wsrep_sst_method=mariabackup `
--wsrep_sst_auth=root:Maria@123 `
--wsrep-new-cluster
```

---

### Verify Bootstrap Node

```powershell
podman logs -f mariadb1
```

You should see:

* WSREP initialized
* Galera started
* Cluster synced

Stop logs:

```powershell
CTRL + C
```

---

### Verify Cluster Size

```powershell
podman exec -it mariadb1 mariadb -uroot -p
```

Run:

```sql
SHOW STATUS LIKE 'wsrep_cluster_size';
```

Expected:

```text
1
```

Exit:

```sql
exit
```

---

### Start mariadb2

```powershell
podman run -d `
--name mariadb2 `
--hostname mariadb2 `
--network venkat-net `
-v mariadb2-data:/var/lib/mysql `
-e MARIADB_ROOT_PASSWORD="Maria@123" `
docker.io/mariadb:11.4 `
--wsrep_on=ON `
--wsrep_provider=/usr/lib/galera/libgalera_smm.so `
--wsrep_cluster_name=galera_cluster `
--wsrep_cluster_address=gcomm://mariadb1 `
--wsrep_node_name=galera2 `
--wsrep_node_address=mariadb2 `
--binlog_format=ROW `
--default-storage-engine=InnoDB `
--innodb_autoinc_lock_mode=2 `
--wsrep_sst_method=mariabackup `
--wsrep_sst_auth=root:Maria@123
```

---

### Start mariadb3

```powershell
podman run -d `
--name mariadb3 `
--hostname mariadb3 `
--network venkat-net `
-v mariadb3-data:/var/lib/mysql `
-e MARIADB_ROOT_PASSWORD="Maria@123" `
docker.io/mariadb:11.4 `
--wsrep_on=ON `
--wsrep_provider=/usr/lib/galera/libgalera_smm.so `
--wsrep_cluster_name=galera_cluster `
--wsrep_cluster_address=gcomm://mariadb1 `
--wsrep_node_name=galera3 `
--wsrep_node_address=mariadb3 `
--binlog_format=ROW `
--default-storage-engine=InnoDB `
--innodb_autoinc_lock_mode=2 `
--wsrep_sst_method=mariabackup `
--wsrep_sst_auth=root:Maria@123
```

---

### Verify Final Cluster Size

```powershell
podman exec -it mariadb1 mariadb -uroot -p
```

Run:

```sql
SHOW STATUS LIKE 'wsrep_cluster_size';
```

Expected:

```text
3
```

Your cluster is now successfully working with 3 nodes. 

---

### Create MaxScale User

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

### Create MaxScale Configuration File

```powershell
notepad E:\podman-instances\mysql-mariadb\maxscale\maxscale.cnf
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

Save and close.

---

### Start MaxScale

```powershell
podman run -d `
--name maxscale `
--hostname maxscale `
--network venkat-net `
-p 3307:3306 `
-v E:\podman-instances\mysql-mariadb\maxscale\maxscale.cnf:/etc/maxscale.cnf:ro `
docker.io/mariadb/maxscale:24.02 `
bash -c "apt update && apt install mariadb-client -y && maxscale --user=root --nodaemon"
```

---

### Verify MaxScale
```
podman ps
podman logs -f maxscale
```

```powershell
podman exec -it maxscale maxctrl list servers
```

Expected:

* All servers Running
* One node Master

---

### Connect Through MaxScale

```powershell
podman exec -it mariadb1 mariadb -h maxscale -P 3306 -u maxuser -p
```
Output
```
PS C:\Users\venkat> podman exec -it mariadb1 mariadb -h maxscale -P 3306 -u maxuser -p
Enter password:
ERROR 2026 (HY000): TLS/SSL error: SSL is required, but the server does not support it
PS C:\Users\venkat>
```
#### Disable SSL and connect 
```
podman exec -it mariadb1 mariadb --ssl=0 -h maxscale -P 3306 -u maxuser -p
or
podman exec -it mariadb1 mariadb --skip-ssl -h maxscale -P 3306 -u maxuser -p
```

Password:

```text
maxpwd
```

---

### Test Replication

```sql
CREATE DATABASE venkatdb;
```

Check from another node:

```powershell
podman exec -it mariadb2 mariadb -uroot -p
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

```powershell
podman stop mariadb1
```

Verify:

```powershell
podman exec -it maxscale maxctrl list servers
```

Another node should become primary automatically.

---

### Stop Environment

```powershell
podman stop mariadb1 mariadb2 mariadb3 maxscale
```

---

### Start Environment

Start bootstrap node first:

```powershell
podman start mariadb1
```

Then:

```powershell
podman start mariadb2 mariadb3 maxscale
```

---

### Remove Environment

```powershell
podman rm -f mariadb1 mariadb2 mariadb3 maxscale
```

```powershell
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

### Primary Installation Steps

```text
/mysql-data  --> Data files
/mysql-conf  --> Configuration files
```

Directory:

```text
E:\podman-instances\mysql-mariadb\mysql\mysql-pr

├── Dockerfile
└── my.cnf
```

### Important Design Decision

The official `mysql:8.4` image is designed around:

```text
/var/lib/mysql
```

If you want to use:

```text
/mysql-data
```

then we should **not use the MySQL image entrypoint to initialize the database automatically**. Instead, we'll initialize `/mysql-data` ourselves after the container starts.

---

## Step 1: my.cnf

Create:

```ini
[mysqld]

server-id=1

datadir=/mysql-data

socket=/mysql-data/mysql.sock
pid-file=/mysql-data/mysql.pid

log-error=/mysql-data/error.log

log_bin=mysql-bin

gtid_mode=ON
enforce_gtid_consistency=ON

binlog_format=ROW
skip-name-resolve
```

---

## Step 2: Dockerfile

```dockerfile
FROM mysql:8.4

USER root

RUN microdnf install -y \
    procps \
    iputils \
    nano \
    net-tools \
    hostname \
    telnet \
    nmap-ncat \
    bind-utils \
    tar \
    gzip \
    && microdnf clean all

RUN mkdir -p /mysql-data \
    && mkdir -p /mysql-conf \
    && chown -R mysql:mysql /mysql-data \
    && chown -R mysql:mysql /mysql-conf

COPY my.cnf /mysql-conf/my.cnf

RUN chmod 644 /mysql-conf/my.cnf

CMD ["bash"]
```

Notice:

```dockerfile
CMD ["bash"]
```

We are intentionally **not** starting MySQL yet.

---

## Step 3: Build Image

Open PowerShell:

```powershell
cd E:\podman-instances\mysql-mariadb\mysql\mysql-pr

podman build -t mysql-pr-image:8.4 .
```

Verify:

```powershell
podman images
```

---

## Step 4: Create Volume

```powershell
podman volume create mysql-pr-data
```

Verify:

```powershell
podman volume ls
```

---

## Step 5: Create Network

```powershell
podman network create mysql-net
```

---

## Step 6: Start Container

PowerShell syntax:

```powershell
podman run -dit `
  --name mysql-pr `
  --hostname mysql-pr `
  --network mysql-net `
  -p 3306:3306 `
  -v mysql-pr-data:/mysql-data `
  mysql-pr-image:8.4
```

Verify:

```powershell
podman ps
```

---

## Step 7: Login Container

```powershell
podman exec -it mysql-pr bash
```

---

## Step 8: Verify Config

Inside container:

```bash
ls -l /mysql-conf

cat /mysql-conf/my.cnf
```

---

## Step 9: Initialize Data Directory

Inside container:

```bash
mysqld \
  --initialize-insecure \
  --user=mysql \
  --datadir=/mysql-data
```

Verify:

```bash
ls -ltr /mysql-data
```

Expected:

```text
auto.cnf
ibdata1
mysql/
performance_schema/
sys/
```

---

## Step 10: Start MySQL

Inside container:

```bash
mysqld \
  --defaults-file=/mysql-conf/my.cnf \
  --user=mysql &
```

Verify:

```bash
ps -ef | grep mysqld
```

---

## Step 11: Connect

```bash
mysql -uroot \
  --socket=/mysql-data/mysql.sock
```

---

## Step 12: Verify Replication Settings

```sql
SHOW VARIABLES LIKE 'server_id';

SHOW VARIABLES LIKE 'log_bin';

SHOW VARIABLES LIKE 'gtid_mode';

SHOW VARIABLES LIKE 'datadir';
```

Expected:

```text
server_id = 1
log_bin = ON
gtid_mode = ON
datadir = /mysql-data/
```

---

## Step 13: Create Replication User

```sql
CREATE USER 'repl'@'%' IDENTIFIED BY 'Repl@123';

GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

FLUSH PRIVILEGES;
```

At this point, your **mysql-pr (Primary)** is ready.

Then we create:

```text
mysql-rp1
server-id=2

mysql-rp2
server-id=3
```

using the same image and separate volumes:

```powershell
mysql-rp1-data
mysql-rp2-data
```

and configure GTID replication. This approach keeps `/mysql-data` and `/mysql-conf` exactly as you wanted and avoids the official image overriding your custom data directory.

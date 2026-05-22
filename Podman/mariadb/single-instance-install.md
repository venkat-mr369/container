#### single instance installation of mariadb 
* replication
* Galera
* ProxySQL
* MaxScale
* PMM
* backups

#### Recommended structure:

```text id="kl7hcv"
E:\podman-instances\mysql-mariadb\
│
├── single-mariadb\
│   ├── config\
│   │   ├── server.cnf
│   │   └── client.cnf
│   │
│   ├── data\
│   │
│   ├── logs\
│   │
│   ├── Dockerfile
│   │
│   ├── run.ps1
│   │
│   └── README.md
```

---

### 1. server.cnf

File:

```text id="j7k3f6"
E:\podman-instances\mysql-mariadb\single-mariadb\config\server.cnf
```

Content:

```ini id="2r2bxa"
[mysqld]

server-id=1
port=3306
bind-address=0.0.0.0

max_connections=300

innodb_buffer_pool_size=512M
innodb_log_file_size=128M

slow_query_log=1
slow_query_log_file=/var/log/mysql/mariadb-slow.log

log_error=/var/log/mysql/mariadb-error.log

character-set-server=utf8mb4
collation-server=utf8mb4_general_ci

default_storage_engine=InnoDB

skip-name-resolve
```

---

### 2. client.cnf

File:

```text id="p12bgr"
config\client.cnf
```

Content:

```ini id="ebq1az"
[client]
default-character-set=utf8mb4
```

---

### 3. Dockerfile

File:

```text id="gr5u22"
single-mariadb\Dockerfile
```

Content:

```dockerfile id="shjve0"
FROM mariadb:11.8.7-ubi9

USER root

RUN microdnf install -y \
    procps \
    iputils \
    vim \
    net-tools \
    hostname \
    && microdnf clean all
```

---

### 4. Build Image

PowerShell:

```powershell id="p1i0g4"
cd E:\podman-instances\mysql-mariadb\single-mariadb
```

Build:

```powershell id="x6spgg"
podman build -t venkat-mariadb:11.8.7 .
```

Verify:

```powershell id="wpmy5m"
podman images
```

---

### 5. run.ps1

File:

```text id="tspulq"
single-mariadb\run.ps1
```

Content:

```powershell id="t50p1x"
podman rm -f single-mariadb

podman run -d `
--name single-mariadb `
--hostname single-mariadb `
--memory=2g `
--cpus=2 `
-p 3306:3306 `
-e MARIADB_ROOT_PASSWORD=Root@123 `
-e TZ=Asia/Kolkata `
-v E:\podman-instances\mysql-mariadb\single-mariadb\data:/var/lib/mysql:Z `
-v E:\podman-instances\mysql-mariadb\single-mariadb\config:/etc/my.cnf.d:Z `
-v E:\podman-instances\mysql-mariadb\single-mariadb\logs:/var/log/mysql:Z `
venkat-mariadb:11.8.7
```

---

### 6. Run Container

PowerShell:

```powershell id="db4iyw"
.\run.ps1
```

---

### 7. Verify

Container:

```powershell id="jlwm5l"
podman ps
```

Logs:

```powershell id="g5t1j0"
podman logs -f single-mariadb
```

Login:

```powershell id="qmn1m5"
podman exec -it single-mariadb mariadb -uroot -p
```

---

### 8. Verify Config

```sql id="3p8mtf"
SHOW VARIABLES LIKE 'max_connections';
```

Expected:

```text id="zwxcyk"
300
```

---

### 9. Useful DBA Commands

Container shell:

```powershell id="hjjlwm"
podman exec -u root -it single-mariadb bash
```

Memory:

```bash id="xtqqr0"
free -h
```

Processes:

```bash id="wrt6sy"
top
```

Ports:

```bash id="1n9y7d"
netstat -tulpn
```

---

### 10. GitHub `.gitignore`

File:

```text id="c59jpv"
.gitignore
```

Content:

```text id="46qsmh"
data/
logs/
```

Never upload DB data files to GitHub.

---

### 11. README.md

Add:

* setup steps
* podman commands
* MariaDB version
* tuning configs
* future roadmap

Example sections:

```text id="fw6gq5"
MariaDB Single Node Lab
Podman Setup
Configuration
Performance Tuning
Storage Engines
Replication (Future)
Galera Cluster (Future)
```

---

This structure is actually close to enterprise containerized DBA lab standards.

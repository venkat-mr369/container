```dockerfile
FROM mysql:8.4

USER root

RUN microdnf install -y \
    procps \
    iputils \
    vim \
    nano \
    net-tools \
    hostname \
    telnet \
    nc \
    bind-utils \
    tar \
    gzip \
    && microdnf clean all
```

Build the image:

```powershell
podman build -t custom-mysql:8.4 .
```

Remove old container:

```powershell
podman rm -f single-mysql
```

Run new container:

```powershell
podman run -d --name single-mysql -e MYSQL_ROOT_PASSWORD=root123 -p 3306:3306 custom-mysql:8.4
```

Connect to container:

```powershell
podman exec -it single-mysql bash
```

Edit MySQL configuration:

```bash
nano /etc/my.cnf
```

or

```bash
vim /etc/my.cnf
```
```bash
/etc/mysql/conf.d/
├── tuning.cnf
├── replication.cnf
├── innodb.cnf
├── security.cnf
```
Useful DBA troubleshooting packages included:

* `vim` / `nano` → file editing
* `procps` → ps, top commands
* `net-tools` → netstat, ifconfig
* `iputils` → ping
* `telnet` → connectivity testing
* `nc` → port testing
* `bind-utils` → dig, nslookup
* `tar`, `gzip` → backup/archive handling

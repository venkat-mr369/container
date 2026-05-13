### TiDB v8.0 Distributed Lab using Podman + HAProxy + Prometheus on Oracle Linux 9

#### Architecture

```text
                    Application / MySQL Client
                               ↓
                    HAProxy (3306)
                               ↓
        ------------------------------------------------
        ↓                    ↓                      ↓
      TiDB1                TiDB2                 TiDB3
      :4000                :4000                 :4000
        ↓                    ↓                      ↓
                   PD Cluster Manager
                         :2379
        ------------------------------------------------
        ↓                    ↓                      ↓
      TiKV1                TiKV2                 TiKV3

                Prometheus Monitoring
```

#### Container Network

Network Name:

```bash
venkat-net
```

#### Lab Requirements

| Component         | Recommended RAM |
| ----------------- | --------------- |
| Oracle Linux 9 VM | 16GB+           |
| CPU               | 4 vCPU minimum  |
| Disk              | 50GB            |

#### Step 1: Install Podman

```bash
dnf install podman -y
```

Verify:

```bash
podman --version
```

#### Step 2: Create Podman Network

```bash
podman network create venkat-net
```

Verify:

```bash
podman network ls
```

Expected:

```bash
venkat-net
```

#### Step 3: Pull Required Images

```bash
podman pull docker.io/pingcap/pd:v8.0.0
podman pull docker.io/pingcap/tikv:v8.0.0
podman pull docker.io/pingcap/tidb:v8.0.0
podman pull docker.io/library/haproxy:latest
podman pull docker.io/prom/prometheus:latest
```

#### Step 4: Start PD Container

```bash
podman run -d \
--name pd \
--hostname pd \
--network venkat-net \
-p 2379:2379 \
-p 2380:2380 \
docker.io/pingcap/pd:v8.0.0 \
--name=pd \
--data-dir=/data/pd \
--client-urls=http://0.0.0.0:2379 \
--peer-urls=http://0.0.0.0:2380 \
--advertise-client-urls=http://pd:2379 \
--initial-cluster=pd=http://pd:2380
```

Verify:

```bash
podman ps
```

#### Step 5: Start TiKV Containers

##### TiKV1

```bash
podman run -d \
--name tikv1 \
--hostname tikv1 \
--network venkat-net \
docker.io/pingcap/tikv:v8.0.0 \
--addr=0.0.0.0:20160 \
--advertise-addr=tikv1:20160 \
--data-dir=/data/tikv \
--pd=pd:2379
```

##### TiKV2

```bash
podman run -d \
--name tikv2 \
--hostname tikv2 \
--network venkat-net \
docker.io/pingcap/tikv:v8.0.0 \
--addr=0.0.0.0:20160 \
--advertise-addr=tikv2:20160 \
--data-dir=/data/tikv \
--pd=pd:2379
```

##### TiKV3

```bash
podman run -d \
--name tikv3 \
--hostname tikv3 \
--network venkat-net \
docker.io/pingcap/tikv:v8.0.0 \
--addr=0.0.0.0:20160 \
--advertise-addr=tikv3:20160 \
--data-dir=/data/tikv \
--pd=pd:2379
```

#### Step 6: Start TiDB SQL Nodes

##### TiDB1

```bash
podman run -d \
--name tidb1 \
--hostname tidb1 \
--network venkat-net \
-p 4001:4000 \
docker.io/pingcap/tidb:v8.0.0 \
--store=tikv \
--path=pd:2379
```

##### TiDB2

```bash
podman run -d \
--name tidb2 \
--hostname tidb2 \
--network venkat-net \
-p 4002:4000 \
docker.io/pingcap/tidb:v8.0.0 \
--store=tikv \
--path=pd:2379
```

##### TiDB3

```bash
podman run -d \
--name tidb3 \
--hostname tidb3 \
--network venkat-net \
-p 4003:4000 \
docker.io/pingcap/tidb:v8.0.0 \
--store=tikv \
--path=pd:2379
```

#### Step 7: Verify Cluster Containers

```bash
podman ps
```

Expected containers:

```text
pd
tikv1
tikv2
tikv3
tidb1
tidb2
tidb3
```

#### Step 8: Install MySQL Client

```bash
dnf install mysql -y
```

Connect:

```bash
mysql -h 127.0.0.1 -P 4001 -u root
```

Test:

```sql
SELECT tidb_version();
```

#### Step 9: Create HAProxy Configuration

Create configuration file:

```bash
mkdir -p /root/haproxy
vi /root/haproxy/haproxy.cfg
```

Paste:

```cfg
global
    daemon
    maxconn 4096

defaults
    mode tcp
    timeout connect 10s
    timeout client 1m
    timeout server 1m

frontend tidb_frontend
    bind *:3306
    default_backend tidb_backend

backend tidb_backend
    balance roundrobin
    option tcp-check

    server tidb1 tidb1:4000 check
    server tidb2 tidb2:4000 check
    server tidb3 tidb3:4000 check

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
```

#### Step 10: Start HAProxy Container

```bash
podman run -d \
--name haproxy \
--hostname haproxy \
--network venkat-net \
-p 3306:3306 \
-p 8404:8404 \
-v /root/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:Z \
docker.io/library/haproxy:latest
```

Verify:

```bash
podman ps
```

#### Step 11: Connect Through HAProxy

Applications should connect only to:

```bash
mysql -h 127.0.0.1 -P 3306 -u root
```

Check node rotation:

```sql
SELECT @@hostname;
```

Multiple logins should rotate across:

```text
tidb1
tidb2
tidb3
```

#### Step 12: HAProxy Monitoring Page

Open browser:

```text
http://SERVER-IP:8404/stats
```

You can monitor:

| Metric         | Description          |
| -------------- | -------------------- |
| UP/DOWN        | TiDB node health     |
| Sessions       | Active connections   |
| Traffic        | SQL traffic          |
| Backend Status | Load balancing state |

#### Step 13: Configure Prometheus

Create directory:

```bash
mkdir -p /root/prometheus
```

Create configuration:

```bash
vi /root/prometheus/prometheus.yml
```

Paste:

```yaml
global:
  scrape_interval: 15s

scrape_configs:

  - job_name: 'pd'
    static_configs:
      - targets: ['pd:2379']

  - job_name: 'tidb'
    static_configs:
      - targets:
          - 'tidb1:10080'
          - 'tidb2:10080'
          - 'tidb3:10080'

  - job_name: 'tikv'
    static_configs:
      - targets:
          - 'tikv1:20180'
          - 'tikv2:20180'
          - 'tikv3:20180'
```

#### Step 14: Start Prometheus Container

```bash
podman run -d \
--name prometheus \
--hostname prometheus \
--network venkat-net \
-p 9090:9090 \
-v /root/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z \
docker.io/prom/prometheus:latest
```

#### Step 15: Access Prometheus

Open browser:

```text
http://SERVER-IP:9090
```

Useful checks:

```text
up
```

You should see metrics from:

```text
pd
tidb1
tidb2
tidb3
tikv1
tikv2
tikv3
```

#### Step 16: Failure Testing

##### Stop TiDB1

```bash
podman stop tidb1
```

Reconnect:

```bash
mysql -h 127.0.0.1 -P 3306 -u root
```

Connection should still work.

HAProxy routes traffic to:

```text
tidb2
tidb3
```

#### Step 17: Verify HAProxy Health

Open:

```text
http://SERVER-IP:8404/stats
```

You should see:

```text
tidb1 = DOWN
tidb2 = UP
tidb3 = UP
```

#### Step 18: Restart Failed Node

```bash
podman start tidb1
```

HAProxy automatically adds node back.

#### Useful Podman Commands

##### View logs

```bash
podman logs tidb1
podman logs tikv1
podman logs pd
```

##### Enter container

```bash
podman exec -it tidb1 /bin/sh
```

##### Stop all containers

```bash
podman stop $(podman ps -aq)
```

##### Start all containers

```bash
podman start $(podman ps -aq)
```

##### Remove all containers

```bash
podman rm -f $(podman ps -aq)
```

#### Important Architecture Understanding

| Layer      | Responsibility                           |
| ---------- | ---------------------------------------- |
| HAProxy    | Load balancing and failover              |
| TiDB       | SQL parsing and query processing         |
| PD         | Cluster metadata and scheduling          |
| TiKV       | Distributed storage and Raft replication |
| Prometheus | Monitoring and metrics                   |

#### Real-Time Enterprise Mapping

| Lab Component | Enterprise Equivalent       |
| ------------- | --------------------------- |
| Podman        | Kubernetes/OpenShift        |
| HAProxy       | F5/NLB/Ingress              |
| Prometheus    | Enterprise Monitoring Stack |
| TiKV          | Distributed storage layer   |
| TiDB          | Stateless SQL layer         |

#### Interview Questions

##### Why use HAProxy with TiDB?

Answer:

```text
TiDB nodes are stateless SQL nodes. HAProxy provides a single entry point and automatically redirects application traffic if one TiDB node fails.
```

##### What happens if one TiKV fails?

Answer:

```text
TiKV uses Raft replication. Other replicas continue serving data automatically.
```

##### What happens if one TiDB node fails?

Answer:

```text
HAProxy removes the failed node and redirects traffic to remaining TiDB nodes.
```

##### Why is TiDB considered cloud-native?

Answer:

```text
Because compute and storage are separated, components are horizontally scalable, and the architecture fits containerized environments like Kubernetes.
```

#### Final Learning Outcome

This single Podman lab teaches:

* Distributed SQL
* Raft consensus
* Stateless SQL architecture
* Load balancing
* Failover
* Container networking
* Prometheus monitoring
* DBSRE concepts
* Cloud-native database design
* Production-style HA architecture

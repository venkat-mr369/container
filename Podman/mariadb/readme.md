A 3-node cluster is strongly recommended over a 2-node cluster because Galera Cluster depends on quorum-based decision making. 
With only 2 nodes, there is a higher risk of split-brain scenarios, while 3 nodes provide stable quorum management and better fault tolerance.

Recommended Lab Architecture:

* MariaDB Galera Node 1
* MariaDB Galera Node 2
* MariaDB Galera Node 3
* MaxScale Proxy Layer

Recommended System Requirements:

* Minimum 16 GB RAM for smooth operation
* 4 CPU cores or higher
* At least 20 GB free storage

Suggested Versions:

* MariaDB 10.11 LTS or MariaDB 11.x
* MaxScale 24.x

Create Podman Network:

```bash
podman network create mariadb-net
```

Architecture Diagram:

```text
                +----------------+
                |    MaxScale    |
                |    Port 3306   |
                +--------+-------+
                         |
     -----------------------------------------
     |                 |                     |
+---------+      +---------+         +---------+
| MDB1    |      | MDB2    |         | MDB3    |
| Galera  |      | Galera  |         | Galera  |
+---------+      +---------+         +---------+
```

Concepts You Can Practice:

* Galera synchronous replication
* Multi-master database architecture
* Automatic failover handling
* Read/write splitting using MaxScale
* Node crash and recovery testing
* SST and IST synchronization methods
* Load balancing
* Backup and restore validation
* Cluster health monitoring

This setup is highly valuable for interviews and hands-on learning because it demonstrates practical experience with:

* Distributed database clustering
* High availability architectures
* Proxy and routing layers
* Real-time replication technologies

Example Interview Statement:
“I built a local MariaDB Galera 3-node cluster using Podman containers with MaxScale for load balancing and failover testing. I practiced node recovery, synchronous replication, read/write splitting, and cluster monitoring in a containerized environment.”

Additional Note:
In the MariaDB ecosystem, MaxScale is the preferred enterprise-grade proxy solution because it provides:

* Intelligent query routing
* Read/write splitting
* Automatic failover support
* Query filtering
* Security masking features
* Monitoring and traffic control

This makes it more advanced and feature-rich compared to traditional proxy layers in many environments.

If needed, I can also help you create:

* Complete Podman deployment commands
* Full Galera cluster configuration
* MaxScale configuration files
* Persistent volume setup
* Podman Compose deployment
* Prometheus and Grafana monitoring integration
* GitHub-ready documentation with diagrams and architecture flow

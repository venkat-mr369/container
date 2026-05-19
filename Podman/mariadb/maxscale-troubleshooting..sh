# =========================================================
# MAXSCALE TROUBLESHOOTING COMMANDS
# =========================================================

# Check maxscale container running or not
podman ps

# Check all containers including exited
podman ps -a

# Check maxscale logs
podman logs maxscale

# Follow live logs
podman logs -f maxscale

# Enter maxscale container
podman exec -it maxscale bash

# Check MaxScale server status
podman exec -it maxscale maxctrl list servers

# Check services
podman exec -it maxscale maxctrl list services

# Check monitors
podman exec -it maxscale maxctrl list monitors

# Check listeners
podman exec -it maxscale maxctrl list listeners

# Show sessions/connections
podman exec -it maxscale maxctrl list sessions

# Show MaxScale modules
podman exec -it maxscale maxctrl list modules

# Show current connections
podman exec -it maxscale maxctrl show service RW-Service

# Show server detailed info
podman exec -it maxscale maxctrl show server server1

# Show monitor details
podman exec -it maxscale maxctrl show monitor Galera-Monitor

# Reload MaxScale config without restart
podman exec -it maxscale maxctrl reload config

# Restart monitor
podman exec -it maxscale maxctrl restart monitor Galera-Monitor

# Stop monitor
podman exec -it maxscale maxctrl stop monitor Galera-Monitor

# Start monitor
podman exec -it maxscale maxctrl start monitor Galera-Monitor

# Check MaxScale version
podman exec -it maxscale maxctrl --version

# Verify listener ports
podman exec -it maxscale netstat -tulnp

# Check if MaxScale port reachable
telnet 127.0.0.1 3307

# =========================================================
# GALERA TROUBLESHOOTING COMMANDS
# =========================================================

# Check cluster size
podman exec -it mariadb1 mariadb -uroot -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"

# Check cluster status
podman exec -it mariadb1 mariadb -uroot -p -e "SHOW STATUS LIKE 'wsrep_cluster_status';"

# Check node state
podman exec -it mariadb1 mariadb -uroot -p -e "SHOW STATUS LIKE 'wsrep_local_state_comment';"

# Check if node ready
podman exec -it mariadb1 mariadb -uroot -p -e "SHOW STATUS LIKE 'wsrep_ready';"

# Check connected nodes
podman exec -it mariadb1 mariadb -uroot -p -e "SHOW STATUS LIKE 'wsrep_connected';"

# Check incoming addresses
podman exec -it mariadb1 mariadb -uroot -p -e "SHOW STATUS LIKE 'wsrep_incoming_addresses';"

# Check cluster UUID
podman exec -it mariadb1 mariadb -uroot -p -e "SHOW STATUS LIKE 'wsrep_cluster_state_uuid';"

# Check node state transfer
podman exec -it mariadb1 mariadb -uroot -p -e "SHOW STATUS LIKE 'wsrep_local_state_uuid';"

# Check replication health
podman exec -it mariadb1 mariadb -uroot -p -e "SHOW STATUS LIKE 'wsrep%';"

# =========================================================
# NODE FAILURE TESTING
# =========================================================

# Stop one node
podman stop mariadb1

# Verify failover in MaxScale
podman exec -it maxscale maxctrl list servers

# Start node again
podman start mariadb1

# Check rejoin logs
podman logs -f mariadb1

# =========================================================
# SST / IST TROUBLESHOOTING
# =========================================================

# Check SST progress
podman logs mariadb1 | findstr SST

# Check wsrep errors
podman logs mariadb1 | findstr WSREP

# Check donor/joiner messages
podman logs mariadb1 | findstr donor

# =========================================================
# NETWORK TROUBLESHOOTING
# =========================================================

# Check podman network
podman network ls

# Inspect network
podman network inspect venkat-net

# Ping between containers
podman exec -it mariadb1 ping mariadb2

# DNS resolution test
podman exec -it mariadb1 nslookup mariadb2

# =========================================================
# DATABASE TESTING
# =========================================================

# Connect through MaxScale
podman exec -it mariadb2 mariadb --skip-ssl -h maxscale -P 3306 -u maxuser -p

# Create test database
CREATE DATABASE testdb;

# Verify replication
SHOW DATABASES;

# Create test table
USE testdb;

CREATE TABLE emp (
  id INT PRIMARY KEY,
  name VARCHAR(100)
);

# Insert data
INSERT INTO emp VALUES (1,'Venkata');

# Verify from another node
SELECT * FROM emp;

# =========================================================
# PERFORMANCE / STATUS COMMANDS
# =========================================================

# Show processlist
SHOW PROCESSLIST;

# Show Galera variables
SHOW VARIABLES LIKE 'wsrep%';

# Show MaxScale server stats
podman exec -it maxscale maxctrl show servers

# Check MaxScale sessions
podman exec -it maxscale maxctrl list sessions

# =========================================================
# CLEANUP COMMANDS
# =========================================================

# Stop all containers
podman stop mariadb1 mariadb2 mariadb3 maxscale

# Remove containers
podman rm -f mariadb1 mariadb2 mariadb3 maxscale

# Remove volumes
podman volume rm mariadb1-data mariadb2-data mariadb3-data maxscale-data

# Remove network
podman network rm venkat-net

### 📦 Container Commands KBArticle

### 🧠 Overview

This document covers:

* Moving Podman (WSL) storage from C drive to another drive
* Essential container (Docker/Podman) commands for practice

---

### 🚀 Part 1: Move Podman Storage to E Drive (Windows)

### 🔍 Background

Podman Desktop on Windows uses **WSL (Windows Subsystem for Linux)** internally.
To free up space on the C drive, you can move the Podman machine to another drive.

---

## ✅ Steps

### 🔴 Step 1: Stop WSL

```bash
wsl --shutdown
```

---

### 🔴 Step 2: List WSL Distributions

```bash
wsl --list --verbose
```

👉 Look for:

```
podman-machine-default
```

---

### 🔴 Step 3: Export Podman Machine

```bash
wsl --export podman-machine-default E:\podman-instances\podman.tar
```

---

### 🔴 Step 4: Unregister Existing Distribution

```bash
wsl --unregister podman-machine-default
```

---

### 🔴 Step 5: Import to E Drive

```bash
wsl --import podman-machine-default E:\podman-instances E:\podman-instances\podman.tar --version 2
```

---

### 🔴 Step 6: Start Podman

```bash
podman machine start
```

---

## ✅ Verification

```bash
podman machine list
```

✔ Ensure status shows **Running**

---

## ⚠️ Notes

* Create `E:\podman-instances` before starting
* Export file may be several GB
* Do not interrupt the process

---

# 🐳 Part 2: Container Commands (Docker/Podman)

> These commands apply to both Docker and Podman with minor differences 

---

## 📥 Image Operations

```bash
docker pull ubuntu:16.04
docker image pull nginx
docker search httpd
docker search --filter is-official=true httpd
docker rmi <image_name>
```

---

## 📦 Container Creation & Execution

```bash
docker container create httpd
docker container start <container_id>
docker run httpd
docker run -d httpd
docker run -d --name mycontainer httpd
```

---

## 🖥️ Interactive Mode

```bash
docker run -it ubuntu bash
docker run -it centos bash
```

---

## 📊 Container Listing

```bash
docker ps
docker ps -a
docker ps -aq
```

---

## 🛑 Stop & Remove Containers

```bash
docker stop <container_id>
docker rm <container_id>
docker container rm $(docker ps -aq)
docker container prune
```

---

## 📜 Logs & Inspection

```bash
docker container logs <container_id>
docker container inspect <container_id>
docker container stats <container_id>
```

---

## 🔧 Execute Commands Inside Container

```bash
docker exec -it <container_id> /bin/bash
docker exec -it <container_id> ls /usr/share/nginx/html/
```

---

## 📂 Copy Files

```bash
docker container cp <container_id>:/file.txt .
docker container cp hostfile.txt <container_id>:/
```

---

## 🌐 Networking & Hostname

```bash
docker run -it --name myapp --hostname myhost ubuntu
```

---

## ⏯️ Pause / Resume

```bash
docker container pause <container_id>
docker container unpause <container_id>
```

---

## 🧪 Useful Examples

### Nginx

```bash
docker run -d nginx
docker exec -it <container_id> /bin/bash
```

### BusyBox

```bash
docker run busybox
docker run busybox hostname -i
```

### Alpine Debugging

```bash
docker run -it alpine /bin/sh
top
ip addr
df -h
```

---

## 🧹 Auto Remove Container

```bash
docker run --rm ubuntu
```

---

# 🎯 Summary

* Use WSL export/import to move Podman storage
* Practice container commands for hands-on learning
* Same commands apply to Podman (replace `docker` with `podman`)

---


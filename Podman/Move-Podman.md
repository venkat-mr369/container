---

### 📦 Move Podman (WSL) Storage from C Drive to E Drive (Windows)

### 🧠 Background

Podman Desktop on Windows uses **WSL (Windows Subsystem for Linux)** internally.
To move Podman data from the **C drive to E drive**, you must relocate the WSL distribution.

---

### ✅ Step-by-Step KBArticle

### 🔴 Step 1: Stop WSL

Open PowerShell and run:

```bash
wsl --shutdown
```

---

### 🔴 Step 2: List WSL Distributions

```bash
wsl --list --verbose
```

👉 Look for a distribution like:

```
podman-machine-default
```

---

### 🔴 Step 3: Export the Podman Machine

```bash
wsl --export podman-machine-default E:\podman-instances\podman.tar
```

---

### 🔴 Step 4: Unregister the Existing Distribution

```bash
wsl --unregister podman-machine-default
```

---

### 🔴 Step 5: Import to E Drive

```bash
wsl --import podman-machine-default E:\podman-instances E:\podman-instances\podman.tar --version 2
```

---

### 🔴 Step 6: Start Podman Machine

```bash
podman machine start
```

---

#### ✅ Result

* Podman data is now stored in: `E:\podman-instances`
* C drive space is freed
* Existing setup remains intact

---

### ⚠️ Important Notes

* Create the folder `E:\podman-instances` before starting
* The export file (`podman.tar`) can be several GB in size
* Do not interrupt the process

---

### 🔍 Verification

```bash
podman machine list
```

👉 Ensure the status shows **Running**

---

```ps
PS C:\WINDOWS\system32> wsl --shutdown
PS C:\WINDOWS\system32> wsl --list --verbose
  NAME                      STATE           VERSION
* podman-machine-default    Stopped         2
PS C:\WINDOWS\system32> wsl --export podman-machine-default E:\podman-instances\podman.tar
Export in progress, this may take a few minutes. (802 MB)

The operation completed successfully.
PS C:\WINDOWS\system32> wsl --unregister podman-machine-default
Unregistering.
The operation completed successfully.

PS C:\WINDOWS\system32> wsl --import podman-machine-default E:\podman-instances E:\podman-instances\podman.tar --version 2
The operation completed successfully.
PS C:\WINDOWS\system32> podman machine start
Starting machine "podman-machine-default"
API forwarding listening on: npipe:////./pipe/docker_engine

Docker API clients default to this address. You do not need to set DOCKER_HOST.
Machine "podman-machine-default" started successfully
PS C:\WINDOWS\system32> podman machine list
NAME                    VM TYPE     CREATED        LAST UP            CPUS        MEMORY      DISK SIZE
podman-machine-default  wsl         4 minutes ago  Currently running  4           2GiB        100GiB
```

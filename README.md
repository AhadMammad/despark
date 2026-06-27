# Spark Learning Environment

Spark 3.5.3 cluster with JupyterLab for structured learning across three levels: Beginner, Intermediate, and Advanced.

---

## Prerequisites

| Tool | Minimum version | Check |
|------|-----------------|-------|
| Docker Desktop | 4.x | `docker --version` |
| Docker Compose | 2.x (bundled with Desktop) | `docker compose version` |
| Make | any | `make --version` |
| Free RAM | **8 GB** recommended (6 GB minimum — lower worker memory in `.env`) | |
| Free disk | ~5 GB (images + data) | |

---

## Setup Sequence

### 1. Configure environment

```bash
cp .env.example .env
```

Open `.env` and adjust worker resources to fit your machine:

```bash
SPARK_WORKER_MEMORY=2G   # lower to 1G if RAM is tight
SPARK_WORKER_CORES=2
```

### 2. Build the Jupyter image

This downloads Spark 3.5.3, Delta Lake JARs, the Almond Scala kernel, and all Python packages. Takes **8–15 minutes** on first run.

```bash
make build
```

### 3. Start the cluster

```bash
make up
```

### 4. Verify the cluster

Open the Spark Master UI and confirm **2 workers** are registered:

```bash
make spark-ui          # opens http://localhost:8080
```

### 5. Seed sample data

Generates CSV / JSON datasets used by the notebooks into `data/raw/`:

```bash
make seed-data
```

### 6. Open JupyterLab

```bash
# Print the URL (token is pre-set to: spark-learn)
make jupyter-token
```

Navigate to `http://localhost:8888?token=spark-learn` and open any notebook under `notebooks/`.

---

## Daily Use

```bash
make up            # start everything
make down          # stop everything
make restart       # stop + start
make clean         # remove containers, network, and volumes (KEEPS images)
```

---

## Multi-user on a shared VM

Several people can run their own fully isolated cluster on the **same Ubuntu VM at
the same time**. Each user is keyed off a **username**, which becomes the naming
convention for every Docker object (compose project, containers, images, network,
volumes) and drives automatic, conflict-free host ports and a unique subnet.

```bash
# 1. Provision an instance (writes instances/<name>.env + an isolated workspace)
make new-user USER=alice

# 2. Build that user's images and start their cluster
make build USER=alice
make up    USER=alice

# Every other command takes USER= too:
make status   USER=alice
make submit   USER=alice APP=apps/beginner/word_count.py
make seed-data USER=alice
make logs     USER=alice
make spark-ui USER=alice        # prints this instance's URL
```

A second user runs concurrently with zero conflicts:

```bash
make new-user USER=bob && make build USER=bob && make up USER=bob
make list-users                 # show every instance with its index/ports/subnet
```

**How ports are assigned.** Each user gets an *instance index* (0, 1, 2, …). Ports
are derived from it, so they never overlap:

| Service | Port | (index `i`) |
|---|---|---|
| Spark Master UI | `8080 + i` | alice→8080, bob→8081 |
| Spark Master RPC | `7077 + i` | |
| Worker 1 UI | `8100 + i` | |
| Worker 2 UI | `8200 + i` | |
| JupyterLab | `8800 + i` | |
| Spark app UI 1 / 2 | `4040 + i*2` / `4041 + i*2` | exactly two apps per instance |

The network subnet is `172.(20+i).0.0/24`. Up to ~100 concurrent instances are
supported. `make new-user` also **pre-flights** every port and refuses if one is
already taken on the host.

**Accessing from outside the VM.** All ports already publish on `0.0.0.0`, so they
are reachable at `http://<VM-IP>:<port>` once the VM firewall / cloud security group
allows the relevant port ranges (8080–8199, 8800+, 4040+). `make spark-ui USER=…`
and friends print the exact URLs (using the VM's primary IP).

**Tearing down an instance:**

```bash
make clean USER=alice    # remove alice's containers, network, volumes — KEEPS images
make purge USER=alice    # full teardown: also remove alice's images, workspace + env
```

> Per-user images share Docker layers, so the per-user tags cost almost no extra
> disk. `make clean` keeps them so a restart needs no rebuild.

---

## Ports

| Service | URL | Notes |
|---------|-----|-------|
| Spark Master UI | http://localhost:8080 | Cluster overview, running apps, worker list |
| Worker 1 UI | http://localhost:8081 | Per-executor metrics |
| Worker 2 UI | http://localhost:8082 | Per-executor metrics |
| Application UI | http://localhost:4040 | Live job/stage/task view (only while an app runs) |
| JupyterLab | http://localhost:8888 | Notebooks — token: `spark-learn` |

---

## Submitting a Spark Job

```bash
# Beginner
make submit APP=apps/beginner/word_count.py

# Intermediate
make submit APP=apps/intermediate/etl_pipeline.py

# Advanced (Delta Lake MERGE)
make submit APP=apps/advanced/delta_lake_etl.py
```

The job appears under **Running Applications** in the Spark Master UI while it runs and under **Completed Applications** afterward.

---

## Curriculum

| Level | Notebooks | Key topics |
|-------|-----------|------------|
| **01 Beginner** | 6 | Architecture, RDDs, DataFrames, Spark SQL, file I/O, Spark UI tour |
| **02 Intermediate** | 7 | DataFrame API, joins, window functions, UDFs, partitioning, streaming intro, Scala comparison |
| **03 Advanced** | 6 | AQE & performance tuning, memory management, Delta Lake, stateful streaming, Catalyst internals, UI debugging |

Scala notebooks (Intermediate 07, Advanced 05) use the **Almond kernel** — select "Scala (Spark 3.5)" from the kernel picker in JupyterLab.

---

## Project Layout

```
despark/
├── docker-compose.yml        Cluster definition
├── Makefile                  All commands
├── .env                      Resource settings (gitignored)
├── docker/jupyter/           Custom Jupyter image
├── conf/                     spark-defaults.conf, log4j2.properties
├── notebooks/
│   ├── 01-beginner/
│   ├── 02-intermediate/
│   └── 03-advanced/
├── apps/                     spark-submit examples + data seeder
├── data/                     Sample datasets (gitignored)
└── lecturer-notes/           Instructor materials (gitignored)
```

---

## Troubleshooting

**Workers not appearing in Spark UI**
Wait 15–20 seconds after `make up`. Workers register after the master passes its health check. Run `make logs-master` to watch.

**`make build` fails on Almond download**
The Almond/Coursier step requires internet access. If behind a proxy, set `HTTP_PROXY` / `HTTPS_PROXY` in your shell before running `make build`.

**Notebook can't connect to cluster**
Confirm the cluster is up (`make status`) and the SparkSession uses `spark://spark-master:7077` as the master URL — not `local[*]`.

**`df.write` fails with "cannot create directory" (Linux only)**
On a native Linux host, bind mounts keep numeric file ownership, so the Spark
workers (which run the file-writing tasks) must run as the user that owns the
workspace `data/` dir. The containers are pinned to `HOST_UID:HOST_GID`:

- **Multi-user:** `scripts/provision.sh` captures your `id -u`/`id -g` into
  `instances/<user>.env`. If you provisioned before this was added, re-run
  `make new-user USER=<name>` to refresh the env file, then
  `make rebuild USER=<name>` (the image perms also changed) and `make up USER=<name>`.
- **Single-instance:** set `HOST_UID`/`HOST_GID` in `.env` to your `id -u`/`id -g`,
  then `make rebuild`.

Docker Desktop (Mac/Windows) remaps ownership automatically, so this only affects
native Linux hosts/VMs.

**Out of memory on workers**
Lower `SPARK_WORKER_MEMORY` in `.env` to `1G`, then run `make restart`.

**Port already in use**
Edit the port variables in `.env` (e.g. change `SPARK_MASTER_WEBUI_PORT=8080` to `9080`) and run `make restart`.

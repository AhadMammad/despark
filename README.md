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
make clean         # remove containers, volumes, and built images
```

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

**Out of memory on workers**
Lower `SPARK_WORKER_MEMORY` in `.env` to `1G`, then run `make restart`.

**Port already in use**
Edit the port variables in `.env` (e.g. change `SPARK_MASTER_WEBUI_PORT=8080` to `9080`) and run `make restart`.

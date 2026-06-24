.PHONY: up down build build-base rebuild rebuild-clean restart clean logs status \
        jupyter-token spark-ui worker-1-ui worker-2-ui \
        submit seed-data help

# BuildKit is required for the cache mounts in the Jupyter Dockerfile.
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Shared base image (Python + Java + Spark) that both spark and jupyter build FROM.
SPARK_TARBALL = spark-$(SPARK_VERSION)-bin-hadoop3.tgz
SPARK_CACHE   = docker/base/cache

# Auto-create .env from example on first use
ifeq (,$(wildcard .env))
$(shell cp .env.example .env)
$(info .env created from .env.example — edit it to tune resources)
endif

include .env
export

# ── Cluster lifecycle ──────────────────────────────────────────────────────────

up: build-base
	docker compose up -d
	@echo ""
	@echo "Cluster starting. Spark UI  → http://localhost:$(SPARK_MASTER_WEBUI_PORT)"
	@echo "                  Jupyter   → http://localhost:$(JUPYTER_PORT)?token=spark-learn"

down:
	docker compose down

# Build the shared base image (Python + Java + Spark). The Spark tarball is
# fetched to $(SPARK_CACHE)/ once and reused on every build — even after
# `docker builder prune` — so the ~400 MB download never repeats.
build-base:
	@mkdir -p $(SPARK_CACHE)
	@test -f $(SPARK_CACHE)/$(SPARK_TARBALL) || ( \
		echo "Fetching $(SPARK_TARBALL) (~400 MB, one time)…" && \
		curl -fL --retry 10 --retry-delay 5 --retry-all-errors -C - \
		  -o $(SPARK_CACHE)/$(SPARK_TARBALL).part \
		  "https://archive.apache.org/dist/spark/spark-$(SPARK_VERSION)/$(SPARK_TARBALL)" && \
		mv $(SPARK_CACHE)/$(SPARK_TARBALL).part $(SPARK_CACHE)/$(SPARK_TARBALL) )
	docker build -t despark-base:$(SPARK_VERSION) ./docker/base

build: build-base
	docker compose build spark-master jupyter

# Fast rebuild: reuse the layer cache (only changed layers re-run), then recreate
# containers so the new image is picked up. This is the everyday command.
rebuild: build-base
	docker compose build spark-master jupyter
	docker compose up -d

# True from-scratch build of the spark/jupyter images (ignores layer cache). The
# shared base — and thus the Spark download/extract — is still reused, and
# pip/apt/Coursier downloads come from BuildKit cache mounts, so this stays fast.
rebuild-clean: build-base
	docker compose build --no-cache spark-master jupyter

restart: down up

clean:
	docker compose down -v --remove-orphans
	docker image rm -f $$(docker images -q despark-jupyter 2>/dev/null) 2>/dev/null || true
	docker image rm -f despark-base:$(SPARK_VERSION) 2>/dev/null || true
	@echo "Environment cleaned. (Spark tarball kept in $(SPARK_CACHE)/ for fast rebuilds.)"

# ── Observability ──────────────────────────────────────────────────────────────

logs:
	docker compose logs -f

logs-master:
	docker compose logs -f spark-master

logs-jupyter:
	docker compose logs -f jupyter

status:
	docker compose ps

# ── Browser shortcuts (macOS) ──────────────────────────────────────────────────

spark-ui:
	open http://localhost:$(SPARK_MASTER_WEBUI_PORT)

worker-1-ui:
	open http://localhost:$(SPARK_WORKER1_WEBUI_PORT)

worker-2-ui:
	open http://localhost:$(SPARK_WORKER2_WEBUI_PORT)

jupyter-token:
	@echo "http://localhost:$(JUPYTER_PORT)?token=spark-learn"

app-ui:
	open http://localhost:4040

# ── Job submission ─────────────────────────────────────────────────────────────
# Usage: make submit APP=apps/beginner/word_count.py

submit:
ifndef APP
	$(error APP is not set. Usage: make submit APP=apps/beginner/word_count.py)
endif
	docker exec spark-master spark-submit \
		--master spark://spark-master:7077 \
		/opt/spark-apps/$(APP)

# ── Data seeding ───────────────────────────────────────────────────────────────

seed-data:
	docker exec jupyter python /home/jovyan/apps/seed_data.py
	@echo "Sample datasets written to data/raw/"

# ── Shell access ───────────────────────────────────────────────────────────────

shell-master:
	docker exec -it spark-master bash

shell-worker-1:
	docker exec -it spark-worker-1 bash

shell-jupyter:
	docker exec -it jupyter bash

# ── Help ───────────────────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "  make up              Start the full cluster (master + 2 workers + Jupyter)"
	@echo "  make down            Stop all services"
	@echo "  make build           Build images (uses layer cache — fast)"
	@echo "  make build-base      Build just the shared base image (Python+Java+Spark)"
	@echo "  make rebuild         Fast cached rebuild + recreate containers (everyday)"
	@echo "  make rebuild-clean   From-scratch image build (--no-cache; base reused)"
	@echo "  make restart         down + up"
	@echo "  make clean           Remove containers, volumes, and built images"
	@echo ""
	@echo "  make logs            Follow all container logs"
	@echo "  make status          Show running containers"
	@echo ""
	@echo "  make spark-ui        Open Spark Master UI  (port $(SPARK_MASTER_WEBUI_PORT))"
	@echo "  make worker-1-ui     Open Worker 1 UI      (port $(SPARK_WORKER1_WEBUI_PORT))"
	@echo "  make worker-2-ui     Open Worker 2 UI      (port $(SPARK_WORKER2_WEBUI_PORT))"
	@echo "  make jupyter-token   Print Jupyter URL with token"
	@echo "  make app-ui          Open running app UI   (port 4040)"
	@echo ""
	@echo "  make submit APP=...  Submit a PySpark app to the cluster"
	@echo "                       e.g. make submit APP=apps/beginner/word_count.py"
	@echo "  make seed-data       Generate sample datasets into data/raw/"
	@echo ""

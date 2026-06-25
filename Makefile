.PHONY: up down build build-base fetch-jars rebuild rebuild-clean restart clean purge \
        new-user list-users require-user logs logs-master logs-jupyter status \
        jupyter-token spark-ui worker-1-ui worker-2-ui app-ui \
        submit seed-data shell-master shell-worker-1 shell-jupyter help

# BuildKit is required for the cache mounts in the Jupyter Dockerfile.
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# ── Per-user instance routing ────────────────────────────────────────────────────
# `make <target> USER=alice` runs an isolated instance: its own compose project,
# container/image/network names, host ports, subnet and workspace — all derived by
# scripts/provision.sh and stored in instances/<user>.env. A bare `make <target>`
# (no USER) keeps the original single-instance behavior.
#
# NOTE: USER is normally inherited from the shell environment (your login name).
# Ignore that and only honor an explicit USER= passed on the command line.
ifneq ($(origin USER),command line)
USER :=
endif

ifeq ($(strip $(USER)),)
  ENV_FILE := .env
  PROJECT  := despark
  # Auto-create .env from example on first use (single-instance mode only).
  ifeq (,$(wildcard .env))
    $(shell cp .env.example .env)
    $(info .env created from .env.example — edit it to tune resources)
  endif
else
  ENV_FILE := instances/$(USER).env
  PROJECT  := despark-$(USER)
endif

# Pull the resolved env into Make (missing file is fine — new-user creates it).
-include $(ENV_FILE)
export
unexport USER   # don't leak the (possibly emptied) USER into recipe subshells

COMPOSE := docker compose --env-file $(ENV_FILE) -p $(PROJECT)

# Defaults for single-instance mode; instance env files override these explicitly.
SPARK_VERSION ?= 3.5.3
BASE_IMAGE    ?= despark-base:$(SPARK_VERSION)
SPARK_IMAGE   ?= despark-spark:$(SPARK_VERSION)
JUPYTER_IMAGE ?= despark-jupyter

# Shared base image (Python + Java + Spark) that both spark and jupyter build FROM.
SPARK_TARBALL = spark-$(SPARK_VERSION)-bin-hadoop3.tgz
SPARK_CACHE   = docker/base/cache

# Delta Lake JARs are gitignored (not committed), so a fresh clone must fetch them
# from Maven Central before any image build. See docker/jupyter/jars/README.md.
DELTA_VERSION ?= 3.2.0
JARS_DIR       = docker/jupyter/jars
DELTA_SPARK_JAR   = $(JARS_DIR)/delta-spark_2.12-$(DELTA_VERSION).jar
DELTA_STORAGE_JAR = $(JARS_DIR)/delta-storage-$(DELTA_VERSION).jar
MAVEN = https://repo1.maven.org/maven2/io/delta

# Host address used when printing UI URLs (first non-loopback IP, else localhost).
HOST := $(shell hostname -I 2>/dev/null | awk '{print $$1}')
ifeq ($(strip $(HOST)),)
HOST := localhost
endif

# ── Per-user provisioning ────────────────────────────────────────────────────────

require-user:
ifeq ($(strip $(USER)),)
	$(error USER is not set. Usage: make $(MAKECMDGOALS) USER=<name>)
endif

# Create (or refresh) a user instance env file + isolated workspace.
# Usage: make new-user USER=alice
new-user: require-user
	./scripts/provision.sh $(USER)

# List every provisioned instance with its index and key ports.
list-users:
	@printf "%-16s %-6s %-8s %-8s %-18s\n" USER INDEX SPARKUI JUPYTER SUBNET
	@for f in instances/*.env; do \
		[ -e "$$f" ] || { echo "(none provisioned)"; break; }; \
		. "$$f"; \
		printf "%-16s %-6s %-8s %-8s %-18s\n" \
			"$$INSTANCE" "$$INDEX" "$$SPARK_MASTER_WEBUI_PORT" "$$JUPYTER_PORT" "$$SUBNET"; \
	done

# ── Cluster lifecycle ──────────────────────────────────────────────────────────

up: build-base
	$(COMPOSE) up -d
	@echo ""
	@echo "Cluster starting. Spark UI  → http://$(HOST):$(SPARK_MASTER_WEBUI_PORT)"
	@echo "                  Jupyter   → http://$(HOST):$(JUPYTER_PORT)?token=spark-learn"

down:
	$(COMPOSE) down

# Download the Delta Lake JARs into docker/jupyter/jars/ if missing. The file
# rules below mean an already-present JAR is never re-downloaded.
fetch-jars: $(DELTA_SPARK_JAR) $(DELTA_STORAGE_JAR)

$(DELTA_SPARK_JAR):
	@echo "Fetching $(notdir $@) from Maven Central…"
	curl -fL --retry 5 --retry-delay 3 -o $@ \
	  "$(MAVEN)/delta-spark_2.12/$(DELTA_VERSION)/delta-spark_2.12-$(DELTA_VERSION).jar"

$(DELTA_STORAGE_JAR):
	@echo "Fetching $(notdir $@) from Maven Central…"
	curl -fL --retry 5 --retry-delay 3 -o $@ \
	  "$(MAVEN)/delta-storage/$(DELTA_VERSION)/delta-storage-$(DELTA_VERSION).jar"

# Build the shared base image (Python + Java + Spark). The Spark tarball is
# fetched to $(SPARK_CACHE)/ once and reused on every build — even after
# `docker builder prune` — so the ~400 MB download never repeats. Depends on
# fetch-jars so the Delta JARs exist before the jupyter image COPYs them.
build-base: fetch-jars
	@mkdir -p $(SPARK_CACHE)
	@test -f $(SPARK_CACHE)/$(SPARK_TARBALL) || ( \
		echo "Fetching $(SPARK_TARBALL) (~400 MB, one time)…" && \
		curl -fL --retry 10 --retry-delay 5 --retry-all-errors -C - \
		  -o $(SPARK_CACHE)/$(SPARK_TARBALL).part \
		  "https://archive.apache.org/dist/spark/spark-$(SPARK_VERSION)/$(SPARK_TARBALL)" && \
		mv $(SPARK_CACHE)/$(SPARK_TARBALL).part $(SPARK_CACHE)/$(SPARK_TARBALL) )
	docker build -t $(BASE_IMAGE) ./docker/base

build: build-base
	$(COMPOSE) build spark-master jupyter

# Fast rebuild: reuse the layer cache (only changed layers re-run), then recreate
# containers so the new image is picked up. This is the everyday command.
rebuild: build-base
	$(COMPOSE) build spark-master jupyter
	$(COMPOSE) up -d

# True from-scratch build of the spark/jupyter images (ignores layer cache). The
# shared base — and thus the Spark download/extract — is still reused, and
# pip/apt/Coursier downloads come from BuildKit cache mounts, so this stays fast.
rebuild-clean: build-base
	$(COMPOSE) build --no-cache spark-master jupyter

restart: down up

# Remove this instance's containers, network and anonymous volumes — but KEEP the
# images (and the host-side workspace + Spark tarball cache) for a fast restart.
clean:
	$(COMPOSE) down -v --remove-orphans
	@echo "Cleaned containers, network and volumes for project '$(PROJECT)'."
	@echo "Images kept. (Spark tarball cached in $(SPARK_CACHE)/.)"

# Full teardown of a user instance: clean + remove its per-user images, workspace
# and env file. Requires USER to avoid touching the shared/default objects.
purge: require-user clean
	-docker image rm -f $(SPARK_IMAGE) $(JUPYTER_IMAGE) $(BASE_IMAGE) 2>/dev/null
	-rm -rf instances/$(USER) instances/$(USER).env
	@echo "Purged instance '$(USER)' (images, workspace and env file removed)."

# ── Observability ──────────────────────────────────────────────────────────────

logs:
	$(COMPOSE) logs -f

logs-master:
	$(COMPOSE) logs -f spark-master

logs-jupyter:
	$(COMPOSE) logs -f jupyter

status:
	$(COMPOSE) ps

# ── UI URLs (print; the VM is typically accessed remotely) ──────────────────────

spark-ui:
	@echo "http://$(HOST):$(SPARK_MASTER_WEBUI_PORT)"

worker-1-ui:
	@echo "http://$(HOST):$(SPARK_WORKER1_WEBUI_PORT)"

worker-2-ui:
	@echo "http://$(HOST):$(SPARK_WORKER2_WEBUI_PORT)"

app-ui:
	@echo "http://$(HOST):$(SPARK_APP1_UI_PORT)  (second app: http://$(HOST):$(SPARK_APP2_UI_PORT))"

jupyter-token:
	@echo "http://$(HOST):$(JUPYTER_PORT)?token=spark-learn"

# ── Job submission ─────────────────────────────────────────────────────────────
# Usage: make submit APP=apps/beginner/word_count.py [USER=alice]

submit:
ifndef APP
	$(error APP is not set. Usage: make submit APP=apps/beginner/word_count.py)
endif
	$(COMPOSE) exec -T spark-master spark-submit \
		--master spark://spark-master:7077 \
		/opt/spark-apps/$(APP)

# ── Data seeding ───────────────────────────────────────────────────────────────

seed-data:
	$(COMPOSE) exec -T jupyter python /home/jovyan/apps/seed_data.py
	@echo "Sample datasets written to data/raw/"

# ── Shell access ───────────────────────────────────────────────────────────────

shell-master:
	$(COMPOSE) exec spark-master bash

shell-worker-1:
	$(COMPOSE) exec spark-worker-1 bash

shell-jupyter:
	$(COMPOSE) exec jupyter bash

# ── Help ───────────────────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "  Single-instance:  make <target>"
	@echo "  Multi-user (VM):  make <target> USER=<name>   (run after: make new-user USER=<name>)"
	@echo ""
	@echo "  make new-user USER=  Generate a user's instance env file + workspace"
	@echo "  make list-users      List provisioned instances (index, ports, subnet)"
	@echo ""
	@echo "  make up              Start the cluster (master + 2 workers + Jupyter)"
	@echo "  make down            Stop all services"
	@echo "  make build           Build images (uses layer cache — fast)"
	@echo "  make build-base      Build just the shared base image (Python+Java+Spark)"
	@echo "  make fetch-jars      Download the Delta Lake JARs (auto-run by build)"
	@echo "  make rebuild         Fast cached rebuild + recreate containers (everyday)"
	@echo "  make rebuild-clean   From-scratch image build (--no-cache; base reused)"
	@echo "  make restart         down + up"
	@echo "  make clean           Remove containers, network, volumes — KEEPS images"
	@echo "  make purge USER=     Full teardown: clean + remove images, workspace, env"
	@echo ""
	@echo "  make logs            Follow all container logs"
	@echo "  make status          Show running containers"
	@echo ""
	@echo "  make spark-ui        Print Spark Master UI URL"
	@echo "  make worker-1-ui     Print Worker 1 UI URL"
	@echo "  make worker-2-ui     Print Worker 2 UI URL"
	@echo "  make jupyter-token   Print Jupyter URL with token"
	@echo "  make app-ui          Print the two Spark application UI URLs"
	@echo ""
	@echo "  make submit APP=...  Submit a PySpark app to the cluster"
	@echo "                       e.g. make submit APP=apps/beginner/word_count.py"
	@echo "  make seed-data       Generate sample datasets into data/raw/"
	@echo ""

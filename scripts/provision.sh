#!/usr/bin/env bash
# Provision a per-user Despark instance on a shared VM.
#
# Each username is mapped to a stable integer "instance index". Every Docker
# object (compose project, containers, images, network, volumes) is named after
# the username, and all host ports + the network subnet are derived from the
# index so multiple users can run simultaneously with zero conflicts.
#
# Usage:
#   scripts/provision.sh <username> [WORKER_MEMORY] [WORKER_CORES]
#
# Re-running for an existing user refreshes the env file and keeps the same index.
set -euo pipefail

# ── Locate repo root (this script lives in <root>/scripts) ──────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

INSTANCES_DIR="instances"

# ── Defaults (overridable via args / existing .env.example) ─────────────────────
SPARK_VERSION_DEFAULT="3.5.3"
WORKER_MEMORY_DEFAULT="2G"
WORKER_CORES_DEFAULT="2"

# ── Args ────────────────────────────────────────────────────────────────────────
USERNAME="${1:-}"
WORKER_MEMORY="${2:-$WORKER_MEMORY_DEFAULT}"
WORKER_CORES="${3:-$WORKER_CORES_DEFAULT}"

if [[ -z "$USERNAME" ]]; then
  echo "ERROR: username required.  Usage: scripts/provision.sh <username>" >&2
  exit 1
fi

# Docker-safe name: lowercase, must start alphanumeric, then alnum/dash.
if [[ ! "$USERNAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ERROR: invalid username '$USERNAME'." >&2
  echo "       Use lowercase letters, digits and dashes; must start alphanumeric." >&2
  exit 1
fi

SPARK_VERSION="${SPARK_VERSION:-$SPARK_VERSION_DEFAULT}"

# ── Host identity ───────────────────────────────────────────────────────────────
# On a native Linux VM, bind mounts preserve numeric UID/GID exactly (no Docker
# Desktop remapping). The Spark workers run the file-writing tasks (executors), so
# they — and the Jupyter driver — must run as the UID/GID that owns this user's
# workspace, otherwise `df.write` fails with "cannot create directory". Capture the
# invoking user's identity and pin every container to it via compose `user:`.
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

ENV_FILE="$INSTANCES_DIR/$USERNAME.env"
# Absolute path: compose only treats a volume source as a bind mount (not a named
# volume) when it starts with / or ./ — an absolute path is unambiguous.
WORKSPACE="$ROOT_DIR/$INSTANCES_DIR/$USERNAME"

mkdir -p "$INSTANCES_DIR"

# ── Determine instance index ────────────────────────────────────────────────────
# Reuse the existing index if this user was already provisioned, otherwise pick
# the lowest index not used by any other instance env file, advancing past any
# index whose host ports are already bound by another process.
index_of_file() { grep -E '^INDEX=' "$1" 2>/dev/null | head -1 | cut -d= -f2; }

# Compute the seven host ports for a given index into the *_PORT globals.
# Bands are spaced 100 apart so each service's range (base..base+99) never overlaps
# another's; this caps simultaneous instances at MAX_INDEX (see below).
compute_ports() {
  local i="$1"
  SPARK_MASTER_WEBUI_PORT=$(( 8080 + i ))   # 8080..8179
  SPARK_MASTER_PORT=$(( 7077 + i ))         # 7077..7176
  SPARK_WORKER1_WEBUI_PORT=$(( 8200 + i ))  # 8200..8299
  SPARK_WORKER2_WEBUI_PORT=$(( 8300 + i ))  # 8300..8399
  JUPYTER_PORT=$(( 8800 + i ))              # 8800..8899
  SPARK_APP1_UI_PORT=$(( 4040 + i * 2 ))    # 4040..4238 (two per instance)
  SPARK_APP2_UI_PORT=$(( 4041 + i * 2 ))    # 4041..4239
  SUBNET="172.$(( 20 + i )).0.0/24"         # 172.20.. 172.119
}

# Worker bands are 100 wide, so indices must stay below 100 to avoid band overlap.
MAX_INDEX=99

port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "sport = :$p" 2>/dev/null | grep -q .
  else
    # Fallback (no ss, e.g. macOS): try to connect; success means a listener.
    (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
    return 1
  fi
}

# Returns the name:port pair that is busy for an index, or empty if all free.
index_busy_port() {
  compute_ports "$1"
  local pv name port
  for pv in \
    "Spark master UI:$SPARK_MASTER_WEBUI_PORT" \
    "Spark master RPC:$SPARK_MASTER_PORT" \
    "Worker 1 UI:$SPARK_WORKER1_WEBUI_PORT" \
    "Worker 2 UI:$SPARK_WORKER2_WEBUI_PORT" \
    "JupyterLab:$JUPYTER_PORT" \
    "Spark app UI 1:$SPARK_APP1_UI_PORT" \
    "Spark app UI 2:$SPARK_APP2_UI_PORT"; do
    name="${pv%%:*}"; port="${pv##*:}"
    if port_in_use "$port"; then echo "$port ($name)"; return 0; fi
  done
  return 0
}

REUSED=0
INDEX=""
if [[ -f "$ENV_FILE" ]]; then
  INDEX="$(index_of_file "$ENV_FILE")"
  [[ -n "$INDEX" ]] && REUSED=1
fi

if [[ -z "$INDEX" ]]; then
  # Collect indices already claimed by other instance env files.
  used=" "
  shopt -s nullglob
  for f in "$INSTANCES_DIR"/*.env; do
    [[ "$f" == "$ENV_FILE" ]] && continue
    idx="$(index_of_file "$f")"
    [[ -n "$idx" ]] && used+="$idx "
  done
  shopt -u nullglob

  # Lowest index that is neither claimed by a file nor blocked by a bound port.
  i=0
  while :; do
    if (( i > MAX_INDEX )); then
      echo "ERROR: no free instance slot found (checked 0-$MAX_INDEX)." >&2
      exit 1
    fi
    if [[ "$used" == *" $i "* ]]; then i=$((i + 1)); continue; fi
    busy="$(index_busy_port "$i")"
    if [[ -n "$busy" ]]; then
      echo "Index $i ports busy ($busy) — trying next slot…" >&2
      i=$((i + 1)); continue
    fi
    break
  done
  INDEX="$i"
fi

if (( INDEX > MAX_INDEX )); then
  echo "ERROR: instance index $INDEX exceeds the supported range (max $MAX_INDEX)." >&2
  exit 1
fi

# Finalize ports/subnet for the chosen index.
compute_ports "$INDEX"

# For a re-provisioned user the cluster may already be running on these ports, so
# only pre-flight brand-new instances (the slot search above already verified them,
# this re-check guards against a race between search and write).
if (( ! REUSED )); then
  busy="$(index_busy_port "$INDEX")"
  if [[ -n "$busy" ]]; then
    echo "ERROR: port $busy for index $INDEX became busy. Re-run to pick another slot." >&2
    exit 1
  fi
fi

# ── Image names (per-user tags; layers dedupe via Docker cache) ─────────────────
BASE_IMAGE="despark-base-$USERNAME:$SPARK_VERSION"
SPARK_IMAGE="despark-spark-$USERNAME:$SPARK_VERSION"
JUPYTER_IMAGE="despark-jupyter-$USERNAME:$SPARK_VERSION"
NETWORK_NAME="despark-$USERNAME-net"

# ── Per-user workspace (isolated, writable copies) ──────────────────────────────
# Notebooks / apps / data are user-mutable, so each user gets their own copy.
# conf/ stays shared from the repo (read-only config, identical for everyone).
if [[ ! -d "$WORKSPACE" ]]; then
  mkdir -p "$WORKSPACE"
  cp -r notebooks "$WORKSPACE/notebooks"
  cp -r apps "$WORKSPACE/apps"
  mkdir -p "$WORKSPACE/data/raw"
  echo "Created workspace $WORKSPACE/ (notebooks, apps, data)."
fi

# ── Write the per-user env file ─────────────────────────────────────────────────
cat > "$ENV_FILE" <<EOF
# Generated by scripts/provision.sh — do not edit by hand.
# User instance: $USERNAME  (index $INDEX)

INSTANCE=$USERNAME
INDEX=$INDEX
COMPOSE_PROJECT_NAME=despark-$USERNAME

# Run all containers as the provisioning user so Spark workers (executors) and the
# Jupyter driver write to the bind-mounted workspace as its owner — no UID clash.
HOST_UID=$HOST_UID
HOST_GID=$HOST_GID

SPARK_VERSION=$SPARK_VERSION
SPARK_WORKER_MEMORY=$WORKER_MEMORY
SPARK_WORKER_CORES=$WORKER_CORES

# Per-user image tags
BASE_IMAGE=$BASE_IMAGE
SPARK_IMAGE=$SPARK_IMAGE
JUPYTER_IMAGE=$JUPYTER_IMAGE

# Isolated network
NETWORK_NAME=$NETWORK_NAME
SUBNET=$SUBNET

# Isolated workspace (bind-mounted notebooks/apps/data)
WORKSPACE=$WORKSPACE

# Host ports (derived from index $INDEX)
SPARK_MASTER_WEBUI_PORT=$SPARK_MASTER_WEBUI_PORT
SPARK_MASTER_PORT=$SPARK_MASTER_PORT
SPARK_WORKER1_WEBUI_PORT=$SPARK_WORKER1_WEBUI_PORT
SPARK_WORKER2_WEBUI_PORT=$SPARK_WORKER2_WEBUI_PORT
JUPYTER_PORT=$JUPYTER_PORT

# Exactly two Spark application UIs are published per instance
SPARK_APP1_UI_PORT=$SPARK_APP1_UI_PORT
SPARK_APP2_UI_PORT=$SPARK_APP2_UI_PORT
EOF

# ── Summary ─────────────────────────────────────────────────────────────────────
HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -z "$HOST" ]] && HOST="<VM-IP>"

cat <<EOF

Provisioned instance '$USERNAME' (index $INDEX)
  env file   : $ENV_FILE
  project    : despark-$USERNAME
  network    : $NETWORK_NAME  ($SUBNET)
  images     : $SPARK_IMAGE, $JUPYTER_IMAGE

  Spark UI   : http://$HOST:$SPARK_MASTER_WEBUI_PORT
  Worker 1   : http://$HOST:$SPARK_WORKER1_WEBUI_PORT
  Worker 2   : http://$HOST:$SPARK_WORKER2_WEBUI_PORT
  JupyterLab : http://$HOST:$JUPYTER_PORT?token=spark-learn
  App UIs    : http://$HOST:$SPARK_APP1_UI_PORT , http://$HOST:$SPARK_APP2_UI_PORT

Next:
  make build USER=$USERNAME     # build this user's images
  make up    USER=$USERNAME     # start the instance
EOF

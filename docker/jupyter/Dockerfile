# syntax=docker/dockerfile:1
# Jupyter image (PySpark driver + Almond Scala kernel). Inherits Python 3.11 +
# Java + Spark from the shared base image, so it no longer downloads/extracts
# Spark itself. The slow, stable steps (Delta JARs, Coursier, Almond) come before
# requirements.txt, so editing a Python package doesn't re-trigger the Scala
# kernel download.
ARG BASE_IMAGE=despark-base:3.5.3
FROM ${BASE_IMAGE}

# ── Delta Lake JARs ────────────────────────────────────────────────────────────
# Vendored under ./jars and copied in (no download at build time). To bump the
# Delta version, refresh the files in docker/jupyter/jars/ — see that dir's README.
ENV DELTA_VERSION=3.2.0
COPY jars/delta-spark_2.12-${DELTA_VERSION}.jar \
     jars/delta-storage-${DELTA_VERSION}.jar \
     $SPARK_HOME/jars/

# ── Coursier (arch-aware) ──────────────────────────────────────────────────────
RUN ARCH=$(uname -m) && \
    case $ARCH in \
      x86_64)  CS_URL="https://github.com/coursier/launchers/raw/master/cs-x86_64-pc-linux.gz" ;; \
      aarch64) CS_URL="https://github.com/coursier/launchers/raw/master/cs-aarch64-pc-linux.gz" ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fL "$CS_URL" | gzip -d > /usr/local/bin/cs && chmod +x /usr/local/bin/cs

# ── Almond (Scala 2.12 kernel) ─────────────────────────────────────────────────
# Almond 0.14.0 final was never published to Maven Central for Scala 2.12 (only
# RCs exist); the first stable release is 0.14.1. Use a published version and
# match Scala 2.12.18 — the exact version Spark 3.5.3 ships with.
# We do NOT pass --extra-jars here; Spark JARs are injected into kernel.json below.
ENV ALMOND_VERSION=0.14.1
ENV SCALA_VERSION=2.12.18

# The Coursier cache mount keeps the ~100 MB of Almond/Scala Maven artifacts across
# builds (even --no-cache), so this step doesn't re-fetch them from the network.
RUN --mount=type=cache,target=/root/.cache/coursier,sharing=locked \
    cs launch \
      "almond:${ALMOND_VERSION}" \
      --scala "${SCALA_VERSION}" \
    -- \
      --install \
      --id almond \
      --display-name "Scala (Spark 3.5)" \
    && echo "Almond kernel installed"

# Copy kernel from root's home to a system-wide path so jovyan can find it,
# then inject Spark JARs via CLASSPATH in kernel.json.
RUN KERNEL_SRC=$(find /root -path "*/kernels/almond" -type d 2>/dev/null | head -1) \
    && mkdir -p /usr/local/share/jupyter/kernels \
    && cp -r "$KERNEL_SRC" /usr/local/share/jupyter/kernels/almond \
    && SPARK_CP=$(ls ${SPARK_HOME}/jars/*.jar | tr '\n' ':') \
    && python3 - "$SPARK_CP" <<'PYEOF'
import json, sys
path = "/usr/local/share/jupyter/kernels/almond/kernel.json"
with open(path) as f:
    spec = json.load(f)
spec.setdefault("env", {})["CLASSPATH"] = sys.argv[1]
with open(path, "w") as f:
    json.dump(spec, f, indent=2)
print("Spark CLASSPATH injected into Almond kernel.json")
PYEOF

# ── Python packages ────────────────────────────────────────────────────────────
# Last among the heavy steps, so requirements.txt edits only re-run pip.
COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install jupyterlab==4.2.2 && \
    pip install -r /tmp/requirements.txt

# ── User setup ─────────────────────────────────────────────────────────────────
# Bake a real user at the host UID/GID (images are built per-user, args passed by
# compose). The driver must run as an identity that exists in /etc/passwd — same
# Hadoop UserGroupInformation requirement as the cluster side — and own its home,
# so no world-writable dirs are needed. Guards keep it idempotent.
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN set -eux; \
    getent group  "${HOST_GID}" >/dev/null || groupadd -g "${HOST_GID}" jovyan; \
    getent passwd "${HOST_UID}" >/dev/null || useradd -u "${HOST_UID}" -g "${HOST_GID}" -m -s /bin/bash jovyan; \
    install -d -o "${HOST_UID}" -g "${HOST_GID}" /home/jovyan
WORKDIR /home/jovyan
USER ${HOST_UID}:${HOST_GID}

# ── Jupyter config ─────────────────────────────────────────────────────────────
RUN mkdir -p /home/jovyan/.jupyter && \
    printf "c.ServerApp.ip = '0.0.0.0'\nc.ServerApp.open_browser = False\nc.ServerApp.port = 8888\n" \
    > /home/jovyan/.jupyter/jupyter_server_config.py

ENV PYSPARK_PYTHON=python3
ENV PYSPARK_DRIVER_PYTHON=python3

EXPOSE 8888 4040 4041 4042

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--NotebookApp.token=spark-learn"]

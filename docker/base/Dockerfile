# syntax=docker/dockerfile:1
# Shared base for both the Spark cluster image and the Jupyter image:
# Python 3.11 + Java + an extracted Spark distribution. Building this once means
# the ~400 MB Spark download/extract happens a single time and is reused (cached)
# by every downstream image, instead of being repeated per image.
FROM python:3.11-slim-bookworm

# ── Java + utilities ───────────────────────────────────────────────────────────
# apt cache mounts keep downloaded .deb packages across builds (even --no-cache),
# so re-installs don't re-fetch from the mirror.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        default-jdk-headless \
        curl \
        wget \
        procps \
    && ln -sf $(dirname $(dirname $(readlink -f /usr/bin/java))) /opt/java-home

# Stable cross-arch JAVA_HOME via the symlink above
ENV JAVA_HOME=/opt/java-home
ENV PATH="$JAVA_HOME/bin:$PATH"

# ── Spark ──────────────────────────────────────────────────────────────────────
ENV SPARK_VERSION=3.5.3
ENV SPARK_HOME=/opt/spark
ENV PATH="$SPARK_HOME/bin:$PATH"

# The tarball is pre-fetched onto the host into ./cache by `make build-base`, then
# bind-mounted in — no network pull happens here. Unlike a BuildKit cache mount,
# the host file survives `docker builder prune` / `make clean`, so the slow
# archive.apache.org download never repeats.
RUN --mount=type=bind,source=cache,target=/spark-cache \
    tar -xzf /spark-cache/spark-${SPARK_VERSION}-bin-hadoop3.tgz -C /opt && \
    mv /opt/spark-${SPARK_VERSION}-bin-hadoop3 $SPARK_HOME

# syntax=docker/dockerfile:1
# Spark cluster image (master + workers). Inherits Python 3.11 + Java + Spark from
# the shared base image, so the executor Python version matches the Jupyter driver
# exactly — no PPA, no compilation, and no second Spark download.
ARG BASE_IMAGE=despark-base:3.5.3
FROM ${BASE_IMAGE}

# python3 in this image is Python 3.11 at /usr/local/bin/python3
ENV PYSPARK_PYTHON=/usr/local/bin/python3

# ── Executor-side Python deps ──────────────────────────────────────────────────
# Pandas UDFs / mapInPandas / toPandas serialize with Arrow and run the user's
# Python on the EXECUTORS (the workers), not just the driver. So pandas + pyarrow
# + numpy must exist in this cluster image too, or the executor Python raises
# "ModuleNotFoundError: No module named 'pandas'" the moment a pandas_udf runs.
# Versions are pinned to match the Jupyter driver (docker/jupyter/requirements.txt)
# so the Arrow record-batch format is identical on both ends of the wire. Installed
# as root, before the USER switch below, so it lands in system site-packages.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install \
        pandas==2.2.2 \
        numpy==1.26.4 \
        pyarrow==16.1.0

# Containers run as the invoking host user's UID/GID (compose `user:`, set per
# instance by scripts/provision.sh). That UID MUST exist in /etc/passwd, otherwise
# Hadoop's UserGroupInformation login crashes the master/worker/executor on start
# with "LoginException: invalid null input: name" — it can't resolve a username for
# a bare numeric UID. The images are built per-user, so bake a real user at the
# host UID/GID: a genuine identity, no world-writable files needed. The guards make
# it idempotent if that UID/GID already exists in the base image.
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN set -eux; \
    getent group  "${HOST_GID}" >/dev/null || groupadd -g "${HOST_GID}" spark; \
    getent passwd "${HOST_UID}" >/dev/null || useradd -u "${HOST_UID}" -g "${HOST_GID}" -m -s /bin/bash spark; \
    mkdir -p /opt/spark/work /opt/spark/.ivy2; \
    chown -R "${HOST_UID}:${HOST_GID}" /opt/spark/work /opt/spark/.ivy2

USER ${HOST_UID}:${HOST_GID}
WORKDIR /opt/spark

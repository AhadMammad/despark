# syntax=docker/dockerfile:1
# Spark cluster image (master + workers). Inherits Python 3.11 + Java + Spark from
# the shared base image, so the executor Python version matches the Jupyter driver
# exactly — no PPA, no compilation, and no second Spark download.
ARG BASE_IMAGE=despark-base:3.5.3
FROM ${BASE_IMAGE}

# python3 in this image is Python 3.11 at /usr/local/bin/python3
ENV PYSPARK_PYTHON=/usr/local/bin/python3

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

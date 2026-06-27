# syntax=docker/dockerfile:1
# Spark cluster image (master + workers). Inherits Python 3.11 + Java + Spark from
# the shared base image, so the executor Python version matches the Jupyter driver
# exactly — no PPA, no compilation, and no second Spark download.
ARG BASE_IMAGE=despark-base:3.5.3
FROM ${BASE_IMAGE}

# python3 in this image is Python 3.11 at /usr/local/bin/python3
ENV PYSPARK_PYTHON=/usr/local/bin/python3

# Containers run as the invoking host user's UID (compose `user:`), which has no
# entry in this image's /etc/passwd. Pre-create the dirs the worker/executor must
# write to and make them world-writable (sticky) so ANY UID can use them:
#   /opt/spark/work  — the Worker fails to start if it can't create this
#   /opt/spark/.ivy2 — coursier/ivy cache if a package is ever resolved at runtime
# The `spark` user (UID 185) is kept only as the default identity for runs that
# don't override `user:`. /opt/spark itself stays root-owned/read-only — it's just
# the immutable runtime; only these scratch dirs need to be writable.
RUN useradd -u 185 -m -s /bin/bash spark \
    && mkdir -p /opt/spark/work /opt/spark/.ivy2 \
    && chmod -R 1777 /opt/spark/work /opt/spark/.ivy2

USER spark
WORKDIR /opt/spark

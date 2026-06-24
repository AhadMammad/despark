# syntax=docker/dockerfile:1
# Spark cluster image (master + workers). Inherits Python 3.11 + Java + Spark from
# the shared base image, so the executor Python version matches the Jupyter driver
# exactly — no PPA, no compilation, and no second Spark download.
FROM despark-base:3.5.3

# python3 in this image is Python 3.11 at /usr/local/bin/python3
ENV PYSPARK_PYTHON=/usr/local/bin/python3

# Mirror the UID used by the official apache/spark image. The Spark tarball
# unpacks owned by its packager's UID (1000), not 185, so /opt/spark isn't
# writable by this user — pre-create the worker's executor work dir and hand it
# to spark, otherwise `spark.deploy.worker.Worker` fails to create /opt/spark/work
# on startup and exits.
RUN useradd -u 185 -m -s /bin/bash spark \
    && mkdir -p /opt/spark/work \
    && chown -R 185:0 /opt/spark/work

USER spark
WORKDIR /opt/spark

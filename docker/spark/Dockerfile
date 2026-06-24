# syntax=docker/dockerfile:1
# Spark cluster image (master + workers). Inherits Python 3.11 + Java + Spark from
# the shared base image, so the executor Python version matches the Jupyter driver
# exactly — no PPA, no compilation, and no second Spark download.
FROM despark-base:3.5.3

# python3 in this image is Python 3.11 at /usr/local/bin/python3
ENV PYSPARK_PYTHON=/usr/local/bin/python3

# Mirror the UID used by the official apache/spark image
RUN useradd -u 185 -m -s /bin/bash spark

USER spark
WORKDIR /opt/spark

# Vendored JARs

These JARs are copied into the Jupyter image at build time (see `../Dockerfile`)
instead of being downloaded on every build.

## Contents

| JAR                          | Source (Maven Central)                                    |
| ---------------------------- | --------------------------------------------------------- |
| `delta-spark_2.12-3.2.0.jar` | `io.delta:delta-spark_2.12:3.2.0`                         |
| `delta-storage-3.2.0.jar`    | `io.delta:delta-storage:3.2.0`                            |

The `delta-spark` Scala suffix (`_2.12`) must match Spark's Scala version (3.5.3 → 2.12).

## Refreshing / bumping the Delta version

1. Bump `DELTA_VERSION` in `../Dockerfile` (and the `COPY` filenames).
2. Re-download the matching JARs into this directory:

   ```sh
   DELTA_VERSION=3.2.0
   curl -sL -O "https://repo1.maven.org/maven2/io/delta/delta-spark_2.12/${DELTA_VERSION}/delta-spark_2.12-${DELTA_VERSION}.jar"
   curl -sL -O "https://repo1.maven.org/maven2/io/delta/delta-storage/${DELTA_VERSION}/delta-storage-${DELTA_VERSION}.jar"
   ```

3. Remove the old JARs and rebuild: `make build`.

"""
Advanced — Delta Lake ETL with MERGE (Upsert)
Demonstrates incremental load pattern using Delta MERGE.
Submit with:
  make submit APP=apps/advanced/delta_lake_etl.py
"""
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from delta.tables import DeltaTable

TARGET_PATH = "/opt/spark-data/delta/customers"
SOURCE_PATH = "/opt/spark-data/raw/customers.csv"

spark = (
    SparkSession.builder
    .appName("DeltaLakeETL")
    .master("spark://spark-master:7077")
    .config("spark.sql.extensions",
            "io.delta.sql.DeltaSparkSessionExtension")
    .config("spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog")
    .config("spark.sql.shuffle.partitions", "8")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

# ── Initial load (first run creates the table) ─────────────────────────────────
if not DeltaTable.isDeltaTable(spark, TARGET_PATH):
    print("No Delta table found — performing initial full load...")
    initial = (
        spark.read
        .option("header", "true")
        .option("inferSchema", "true")
        .csv(SOURCE_PATH)
        .withColumn("last_updated", F.current_timestamp())
        .withColumn("is_active", F.lit(True))
    )
    initial.write.format("delta").mode("overwrite").save(TARGET_PATH)
    print(f"Initial load complete: {initial.count()} rows")
else:
    print("Delta table exists — performing incremental MERGE...")

    # Simulate a CDC (change data capture) batch
    # In production this would come from Kafka, Debezium, etc.
    updates = (
        spark.read
        .option("header", "true")
        .option("inferSchema", "true")
        .csv(SOURCE_PATH)
        # Simulate some changed rows and some new rows
        .limit(20)
        .withColumn("email",        F.concat(F.col("email"), F.lit(".updated")))
        .withColumn("last_updated", F.current_timestamp())
        .withColumn("is_active",    F.lit(True))
    )

    target = DeltaTable.forPath(spark, TARGET_PATH)

    (
        target.alias("t")
        .merge(
            updates.alias("s"),
            "t.customer_id = s.customer_id"
        )
        .whenMatchedUpdateAll()
        .whenNotMatchedInsertAll()
        .execute()
    )
    print("MERGE complete.")

# ── Show current state ─────────────────────────────────────────────────────────
current = spark.read.format("delta").load(TARGET_PATH)
print(f"\nCurrent table row count: {current.count()}")
current.show(5, truncate=False)

# ── Show history ───────────────────────────────────────────────────────────────
print("\n=== Delta Table History ===")
DeltaTable.forPath(spark, TARGET_PATH).history().show(truncate=False)

spark.stop()

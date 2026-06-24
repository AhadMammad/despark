"""
Intermediate — ETL Pipeline
Reads raw CSV orders, cleans and enriches them, writes partitioned Parquet.
Submit with:
  make submit APP=apps/intermediate/etl_pipeline.py
"""
import sys
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import DoubleType

INPUT_PATH  = "/opt/spark-data/raw/orders.csv"
OUTPUT_PATH = "/opt/spark-data/processed/orders_enriched"

spark = (
    SparkSession.builder
    .appName("ETLPipeline")
    .master("spark://spark-master:7077")
    .config("spark.sql.shuffle.partitions", "8")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

# ── Extract ────────────────────────────────────────────────────────────────────
print("Reading raw orders...")
raw = (
    spark.read
    .option("header", "true")
    .option("inferSchema", "true")
    .csv(INPUT_PATH)
)
print(f"Raw row count: {raw.count()}")

# ── Transform ──────────────────────────────────────────────────────────────────
clean = (
    raw
    # Drop rows with nulls in critical columns
    .dropna(subset=["order_id", "customer_id", "amount"])
    # Normalise string columns
    .withColumn("category", F.upper(F.trim(F.col("category"))))
    .withColumn("product",  F.trim(F.col("product")))
    # Derive revenue after tax (assume 18%)
    .withColumn("amount",      F.col("amount").cast(DoubleType()))
    .withColumn("tax",         F.round(F.col("amount") * 0.18, 2))
    .withColumn("total_amount", F.round(F.col("amount") + F.col("tax"), 2))
    # Parse date string → DateType
    .withColumn("order_date", F.to_date(F.col("order_date"), "yyyy-MM-dd"))
    .withColumn("year",  F.year("order_date"))
    .withColumn("month", F.month("order_date"))
    # Drop rows with invalid amounts
    .filter(F.col("amount") > 0)
)

# ── Aggregate summary ──────────────────────────────────────────────────────────
summary = (
    clean
    .groupBy("category", "year", "month")
    .agg(
        F.count("order_id").alias("order_count"),
        F.round(F.sum("total_amount"), 2).alias("total_revenue"),
        F.round(F.avg("amount"), 2).alias("avg_order_value"),
    )
    .orderBy("category", "year", "month")
)

print("\n=== Monthly Revenue by Category ===")
summary.show(30, truncate=False)

# ── Load ───────────────────────────────────────────────────────────────────────
print(f"\nWriting enriched data to {OUTPUT_PATH} ...")
(
    clean
    .write
    .mode("overwrite")
    .partitionBy("year", "month")
    .parquet(OUTPUT_PATH)
)
print(f"Done. Clean row count: {clean.count()}")

spark.stop()

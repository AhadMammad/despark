"""
Beginner — Word Count
Classic first Spark job. Submit with:
  make submit APP=apps/beginner/word_count.py
"""
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

spark = (
    SparkSession.builder
    .appName("WordCount")
    .master("spark://spark-master:7077")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

# Sample corpus — in a real job this would be a file read
lines = [
    "Apache Spark is a unified analytics engine for large-scale data processing",
    "Spark provides an interface for programming entire clusters with implicit data parallelism",
    "Spark was developed at UC Berkeley and is now an Apache top-level project",
    "With Spark you can write applications in Java Scala Python R and SQL",
    "Spark can run on Kubernetes Hadoop YARN Mesos or in standalone cluster mode",
]

df = spark.createDataFrame([(l,) for l in lines], ["line"])

word_counts = (
    df
    .select(F.explode(F.split(F.lower(F.col("line")), r"\s+")).alias("word"))
    .filter(F.col("word") != "")
    .groupBy("word")
    .count()
    .orderBy(F.desc("count"))
)

print("\n=== Top 20 words ===")
word_counts.show(20, truncate=False)
print(f"Total unique words: {word_counts.count()}")

spark.stop()

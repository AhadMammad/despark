"""
Data seeder — run via: make seed-data
Generates realistic sample datasets into /home/jovyan/data/raw/
"""
import os
import random
import csv
from datetime import date, timedelta
from faker import Faker

fake = Faker()
random.seed(42)
Faker.seed(42)

BASE = "/home/jovyan/data/raw"
os.makedirs(BASE, exist_ok=True)


def random_date(start="2023-01-01", end="2024-12-31"):
    s = date.fromisoformat(start)
    e = date.fromisoformat(end)
    return s + timedelta(days=random.randint(0, (e - s).days))


# ── orders.csv ────────────────────────────────────────────────────────────────
CATEGORIES = ["Electronics", "Clothing", "Food", "Sports", "Home", "Books"]
PRODUCTS = {
    "Electronics": ["Laptop", "Phone", "Tablet", "Headphones", "Camera"],
    "Clothing":    ["T-Shirt", "Jeans", "Jacket", "Dress", "Sneakers"],
    "Food":        ["Coffee", "Tea", "Chocolate", "Olive Oil", "Pasta"],
    "Sports":      ["Yoga Mat", "Dumbbells", "Running Shoes", "Bottle", "Gloves"],
    "Home":        ["Lamp", "Pillow", "Blanket", "Mug", "Candle"],
    "Books":       ["Novel", "Textbook", "Comic", "Biography", "Guide"],
}

orders_path = os.path.join(BASE, "orders.csv")
with open(orders_path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["order_id", "customer_id", "product", "category", "quantity", "amount", "order_date"])
    for i in range(1, 5001):
        cat = random.choice(CATEGORIES)
        prod = random.choice(PRODUCTS[cat])
        qty = random.randint(1, 10)
        price = round(random.uniform(5.0, 500.0), 2)
        w.writerow([
            f"ORD-{i:05d}",
            f"CUST-{random.randint(1, 500):04d}",
            prod, cat, qty,
            round(qty * price, 2),
            random_date(),
        ])
print(f"  orders.csv          → 5 000 rows")

# ── customers.csv ─────────────────────────────────────────────────────────────
customers_path = os.path.join(BASE, "customers.csv")
with open(customers_path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["customer_id", "name", "email", "city", "country", "signup_date", "tier"])
    for i in range(1, 501):
        w.writerow([
            f"CUST-{i:04d}",
            fake.name(),
            fake.email(),
            fake.city(),
            fake.country(),
            random_date("2020-01-01", "2023-12-31"),
            random.choice(["bronze", "silver", "gold", "platinum"]),
        ])
print(f"  customers.csv       → 500 rows")

# ── employees.csv ─────────────────────────────────────────────────────────────
DEPTS = ["Engineering", "Sales", "Marketing", "Finance", "HR", "Product"]
employees_path = os.path.join(BASE, "employees.csv")
with open(employees_path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["employee_id", "name", "department", "salary", "hire_date", "manager_id"])
    for i in range(1, 201):
        dept = random.choice(DEPTS)
        w.writerow([
            f"EMP-{i:04d}",
            fake.name(),
            dept,
            round(random.uniform(40000, 150000), 2),
            random_date("2015-01-01", "2023-12-31"),
            f"EMP-{random.randint(1, 20):04d}" if i > 20 else None,
        ])
print(f"  employees.csv       → 200 rows")

# ── events.json (for streaming notebooks) ────────────────────────────────────
import json
events_dir = os.path.join(BASE, "events")
os.makedirs(events_dir, exist_ok=True)
events = []
for i in range(1, 1001):
    events.append({
        "event_id":   f"EVT-{i:05d}",
        "sensor_id":  f"SENSOR-{random.randint(1, 10):02d}",
        "temperature": round(random.uniform(15.0, 40.0), 2),
        "humidity":    round(random.uniform(30.0, 90.0), 2),
        "ts":          str(date.today()) + f"T{random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}",
    })
with open(os.path.join(events_dir, "events_batch_1.json"), "w") as f:
    for e in events[:500]:
        f.write(json.dumps(e) + "\n")
with open(os.path.join(events_dir, "events_batch_2.json"), "w") as f:
    for e in events[500:]:
        f.write(json.dumps(e) + "\n")
print(f"  events/             → 1 000 events (2 batch files)")

print("\nAll sample data written to data/raw/")

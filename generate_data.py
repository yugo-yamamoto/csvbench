#!/usr/bin/env python3
"""Generate 100k row test CSV for benchmarking.

The 'notes' column intentionally contains commas, double-quotes, and embedded
newlines so that naive parsers (split on comma / readline) break.
"""

import csv
import random
from datetime import date, timedelta

CATEGORIES = ["Electronics", "Food", "Clothing", "Books", "Sports", "Toys", "Tools", "Health", "Beauty", "Garden"]
REGIONS = ["North", "South", "East", "West", "Central"]
FIRST_NAMES = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry", "Iris", "Jack",
               "Kate", "Liam", "Mia", "Noah", "Olivia", "Paul", "Quinn", "Rose", "Sam", "Tina"]
LAST_NAMES = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Wilson", "Taylor"]

# Notes that exercise all CSV edge cases
NOTES_PLAIN   = ["good", "ok", "fast delivery", "as described", "recommended"]
NOTES_COMMA   = ["ships from Tokyo, Japan", "S, M, or L", "buy 1, get 1 free", "red, blue, or green"]
NOTES_QUOTE   = ['staff said "excellent"', 'rated "A+" quality', 'marked as "new arrival"']
NOTES_NEWLINE = ["line1\nline2", "pros:\ngood quality\nfast", "note:\ncheck size before order"]

NUM_ROWS = 1_000_000
OUTPUT_FILE = "data/test.csv"


def random_date(start: date, end: date) -> str:
    return (start + timedelta(days=random.randint(0, (end - start).days))).isoformat()


def main() -> None:
    random.seed(42)
    start_date = date(2024, 1, 1)
    end_date = date(2024, 12, 31)

    with open(OUTPUT_FILE, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name", "category", "value", "quantity", "date", "region", "notes"])
        for i in range(1, NUM_ROWS + 1):
            name = f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"
            category = random.choice(CATEGORIES)
            value = round(random.uniform(1.0, 999.99), 2)
            quantity = random.randint(1, 100)
            row_date = random_date(start_date, end_date)
            region = random.choice(REGIONS)
            # distribute edge-case notes: 40% plain, 20% each for the other three
            r = random.random()
            if r < 0.40:
                notes = random.choice(NOTES_PLAIN)
            elif r < 0.60:
                notes = random.choice(NOTES_COMMA)
            elif r < 0.80:
                notes = random.choice(NOTES_QUOTE)
            else:
                notes = random.choice(NOTES_NEWLINE)
            writer.writerow([i, name, category, value, quantity, row_date, region, notes])

    print(f"Generated {NUM_ROWS:,} rows -> {OUTPUT_FILE}")


if __name__ == "__main__":
    main()

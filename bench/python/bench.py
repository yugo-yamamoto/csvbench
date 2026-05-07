#!/usr/bin/env python3
"""Python CSV benchmark: read 100k rows and aggregate by category."""

import csv
import sys
import time
from collections import defaultdict
from pathlib import Path

DATA_FILE = Path(__file__).parent.parent.parent / "data" / "test.csv"


def run() -> None:
    totals: dict[str, dict] = defaultdict(lambda: {
        "revenue": 0.0,
        "count": 0,
        "value_sum": 0.0,
        "value_max": float("-inf"),
        "value_min": float("inf"),
    })

    with DATA_FILE.open(newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            cat = row["category"]
            value = float(row["value"])
            qty = int(row["quantity"])
            g = totals[cat]
            g["revenue"] += value * qty
            g["count"] += 1
            g["value_sum"] += value
            if value > g["value_max"]:
                g["value_max"] = value
            if value < g["value_min"]:
                g["value_min"] = value

    print(f"{'Category':<12} {'Count':>8} {'Revenue':>14} {'Avg Value':>12} {'Max':>8} {'Min':>8}")
    print("-" * 66)
    for cat in sorted(totals):
        g = totals[cat]
        avg = g["value_sum"] / g["count"]
        print(f"{cat:<12} {g['count']:>8,} {g['revenue']:>14,.2f} {avg:>12.2f} {g['value_max']:>8.2f} {g['value_min']:>8.2f}")


def main() -> None:
    start = time.perf_counter()
    run()
    elapsed = time.perf_counter() - start
    print(f"\nElapsed: {elapsed:.4f}s")


if __name__ == "__main__":
    main()

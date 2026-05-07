#!/usr/bin/env python3
"""Python + pandas CSV benchmark: streaming via chunksize, aggregate by category."""

import time
from pathlib import Path

import pandas as pd

DATA_FILE = Path(__file__).parent.parent.parent / "data" / "test.csv"
CHUNK_SIZE = 50_000


def run() -> None:
    combined: dict[str, dict] = {}

    for chunk in pd.read_csv(DATA_FILE, chunksize=CHUNK_SIZE):
        chunk = chunk.copy()
        chunk["revenue"] = chunk["value"] * chunk["quantity"]
        agg = chunk.groupby("category", sort=False).agg(
            count=("value", "count"),
            revenue=("revenue", "sum"),
            value_sum=("value", "sum"),
            value_max=("value", "max"),
            value_min=("value", "min"),
        )
        for cat, row in agg.iterrows():
            if cat not in combined:
                combined[cat] = {
                    "count": 0, "revenue": 0.0, "value_sum": 0.0,
                    "value_max": float("-inf"), "value_min": float("inf"),
                }
            g = combined[cat]
            g["count"]    += int(row["count"])
            g["revenue"]  += row["revenue"]
            g["value_sum"]+= row["value_sum"]
            if row["value_max"] > g["value_max"]: g["value_max"] = row["value_max"]
            if row["value_min"] < g["value_min"]: g["value_min"] = row["value_min"]

    print(f"{'Category':<12} {'Count':>8} {'Revenue':>14} {'Avg Value':>12} {'Max':>8} {'Min':>8}")
    print("-" * 66)
    for cat in sorted(combined):
        g = combined[cat]
        avg = g["value_sum"] / g["count"]
        print(f"{cat:<12} {g['count']:>8,} {g['revenue']:>14,.2f} {avg:>12.2f} {g['value_max']:>8.2f} {g['value_min']:>8.2f}")


def main() -> None:
    start = time.perf_counter()
    run()
    elapsed = time.perf_counter() - start
    print(f"\nElapsed: {elapsed:.4f}s")


if __name__ == "__main__":
    main()

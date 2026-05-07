#!/usr/bin/env python3
"""Python + Polars CSV benchmark: lazy scan_csv + group_by."""

import time
from pathlib import Path

import polars as pl

DATA_FILE = str(Path(__file__).parent.parent.parent / "data" / "test.csv")


def run() -> None:
    result = (
        pl.scan_csv(DATA_FILE)
        .with_columns((pl.col("value") * pl.col("quantity")).alias("revenue"))
        .group_by("category")
        .agg(
            pl.col("value").count().alias("count"),
            pl.col("revenue").sum().alias("revenue"),
            pl.col("value").mean().alias("avg_value"),
            pl.col("value").max().alias("value_max"),
            pl.col("value").min().alias("value_min"),
        )
        .sort("category")
        .collect()
    )

    print(f"{'Category':<12} {'Count':>8} {'Revenue':>14} {'Avg Value':>12} {'Max':>8} {'Min':>8}")
    print("-" * 66)
    for row in result.iter_rows(named=True):
        print(
            f"{row['category']:<12} {row['count']:>8,} {row['revenue']:>14,.2f}"
            f" {row['avg_value']:>12.2f} {row['value_max']:>8.2f} {row['value_min']:>8.2f}"
        )


def main() -> None:
    start = time.perf_counter()
    run()
    elapsed = time.perf_counter() - start
    print(f"\nElapsed: {elapsed:.4f}s")


if __name__ == "__main__":
    main()

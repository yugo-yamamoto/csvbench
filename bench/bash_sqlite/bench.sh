#!/usr/bin/env bash
# Bash + SQLite benchmark: bulk-import CSV via sqlite3 CLI, then aggregate.

set -euo pipefail

DATA_FILE="${1:-$(cd "$(dirname "$0")/../.." && pwd)/data/test.csv}"
DB_FILE="/tmp/csvbench_bash_$$.db"

cleanup() { rm -f "$DB_FILE"; }
trap cleanup EXIT

printf '%-12s %8s %14s %12s %8s %8s\n' "Category" "Count" "Revenue" "Avg Value" "Max" "Min"
printf '%0.s-' {1..66}; echo

start_ns=$(date +%s%N)

# Import CSV (sqlite3 infers columns from the header row)
sqlite3 "$DB_FILE" \
  ".mode csv" \
  ".headers on" \
  ".import $DATA_FILE sales"

# Aggregate and format output
sqlite3 "$DB_FILE" <<'SQL'
.headers off
SELECT
  printf('%-12s %8d %14.2f %12.2f %8.2f %8.2f',
    category,
    COUNT(*),
    SUM(value * quantity),
    AVG(value),
    MAX(value),
    MIN(value)
  )
FROM sales
GROUP BY category
ORDER BY category;
SQL

end_ns=$(date +%s%N)
elapsed=$(awk "BEGIN { printf \"%.4f\", ($end_ns - $start_ns) / 1e9 }")

printf '\nElapsed: %ss\n' "$elapsed"

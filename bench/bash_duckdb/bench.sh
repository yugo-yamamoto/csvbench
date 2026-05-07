#!/usr/bin/env bash
set -euo pipefail

DATA="${1:-../../data/test.csv}"
DUCKDB="${DUCKDB_CLI:-duckdb}"

start_ns=$(date +%s%N)

"$DUCKDB" -csv -noheader -c "
SELECT
    category,
    COUNT(*)                      AS count,
    SUM(value * quantity)         AS revenue,
    AVG(value)                    AS avg_value,
    MAX(value)                    AS value_max,
    MIN(value)                    AS value_min
FROM read_csv('$DATA',
    header = true,
    columns = {
        'id':       'INTEGER',
        'name':     'VARCHAR',
        'category': 'VARCHAR',
        'value':    'DOUBLE',
        'quantity': 'INTEGER',
        'date':     'VARCHAR',
        'region':   'VARCHAR',
        'notes':    'VARCHAR'
    }
)
GROUP BY category
ORDER BY category;
" | awk -F',' '
BEGIN {
    printf "%-12s %8s %14s %12s %8s %8s\n", "Category", "Count", "Revenue", "Avg Value", "Max", "Min"
    printf "%s\n", "------------------------------------------------------------------"
}
{
    printf "%-12s %8d %14.2f %12.2f %8.2f %8.2f\n", $1, $2, $3, $4, $5, $6
}'

end_ns=$(date +%s%N)
elapsed=$(echo "scale=4; ($end_ns - $start_ns) / 1000000000" | bc)
printf "\nElapsed: %ss\n" "$elapsed"

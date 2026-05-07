#!/usr/bin/env bash
# Measure peak RSS (kB) for each benchmark implementation.
# Uses /usr/bin/time -v  →  "Maximum resident set size (kbytes)"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DATA="$ROOT/data/test.csv"
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
JAVA_BIN="$JAVA_HOME/bin/java"
DUCKDB_CLI="${DUCKDB_CLI:-/root/.duckdb/cli/latest/duckdb}"

export RBENV_ROOT="${RBENV_ROOT:-$HOME/.rbenv}"
export PATH="$RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH"
source "${HOME}/.cargo/env" 2>/dev/null || true

# peak_kb <label> <cmd...>
peak_kb() {
    local label="$1"; shift
    local kb
    kb=$( { /usr/bin/time -v "$@" > /dev/null; } 2>&1 | grep "Maximum resident" | awk '{print $NF}' )
    printf "%s\t%s\n" "$kb" "$label"
}

echo "Measuring peak memory (RSS) for each implementation..." >&2
echo "This takes a few minutes." >&2
echo "" >&2

results=()

# Python (stdlib csv)
results+=( "$(peak_kb 'Python (stdlib csv)' \
    uv run --python 3.13 "$ROOT/bench/python/bench.py")" )

# Python + pandas
results+=( "$(peak_kb 'Python + pandas' \
    uv run --python 3.13 --with pandas "$ROOT/bench/python_pandas/bench.py")" )

# Python + Polars
results+=( "$(peak_kb 'Python + Polars' \
    bash -c "cd '$ROOT/bench/python_polars' && uv run bench.py '$DATA'")" )

# JavaScript (手書き)
results+=( "$(peak_kb 'JavaScript (手書き)' \
    node "$ROOT/bench/js/bench.mjs")" )

# JavaScript + csv-parse
results+=( "$(peak_kb 'JavaScript + csv-parse' \
    node "$ROOT/bench/js_csvparse/bench.mjs")" )

# JavaScript + PapaParse
results+=( "$(peak_kb 'JavaScript + PapaParse' \
    node "$ROOT/bench/js_papaparse/bench.mjs")" )

# Go
results+=( "$(peak_kb 'Go' \
    bash -c "cd '$ROOT/bench/go' && go run bench.go '$DATA'")" )

# Java (手書き) – compile first if needed
JAVA_OUT="$ROOT/bench/java/out"
mkdir -p "$JAVA_OUT"
"$JAVA_HOME/bin/javac" -d "$JAVA_OUT" "$ROOT/bench/java/BenchCSV.java" 2>/dev/null
results+=( "$(peak_kb 'Java (手書き)' \
    "$JAVA_BIN" -cp "$JAVA_OUT" BenchCSV "$DATA")" )

# Java + univocity-parsers
JAVA_UNI_DIR="$ROOT/bench/java_univocity"
"$JAVA_HOME/bin/javac" -cp "$JAVA_UNI_DIR/lib/univocity-parsers.jar" \
    -d "$JAVA_UNI_DIR" "$JAVA_UNI_DIR/BenchUnivocity.java" 2>/dev/null
results+=( "$(peak_kb 'Java + univocity-parsers' \
    "$JAVA_BIN" -cp "$JAVA_UNI_DIR:$JAVA_UNI_DIR/lib/univocity-parsers.jar" BenchUnivocity "$DATA")" )

# Ruby
results+=( "$(peak_kb 'Ruby (stdlib CSV)' \
    bash -c "cd '$ROOT/bench/ruby' && rbenv local 3.4.8 && ruby bench.rb '$DATA'")" )

# Ruby + SQLite
results+=( "$(peak_kb 'Ruby + SQLite (CLI import)' \
    bash -c "cd '$ROOT/bench/ruby_sqlite_import' && rbenv local 3.4.8 && ruby bench.rb")" )

# Rust (手書き)
results+=( "$(peak_kb 'Rust (手書き)' \
    "$ROOT/bench/rust/target/release/bench" "$DATA")" )

# Rust + csv crate
results+=( "$(peak_kb 'Rust + csv crate' \
    "$ROOT/bench/rust_csv/target/release/bench-csv-crate" "$DATA")" )

# C++
g++ -O2 -std=c++20 -o "$ROOT/bench/cpp/bench" "$ROOT/bench/cpp/bench.cpp" 2>/dev/null
results+=( "$(peak_kb 'C++' \
    "$ROOT/bench/cpp/bench" "$DATA")" )

# Bash + SQLite  (measure the sqlite3 subprocess directly)
results+=( "$(peak_kb 'Bash + SQLite' \
    bash "$ROOT/bench/bash_sqlite/bench.sh" "$DATA")" )

# Bash + DuckDB
results+=( "$(peak_kb 'Bash + DuckDB' \
    bash -c "DUCKDB_CLI='$DUCKDB_CLI' bash '$ROOT/bench/bash_duckdb/bench.sh' '$DATA'")" )

# ── print sorted table ────────────────────────────────────────────────────────
printf "\n%-32s %10s %10s\n" "Implementation" "Peak RSS" "(MB)"
printf "%s\n" "--------------------------------------------------------------"

printf '%s\n' "${results[@]}" | sort -n | while IFS=$'\t' read -r kb label; do
    mb=$(echo "scale=1; $kb / 1024" | bc)
    printf "%-32s %8s KB %8s MB\n" "$label" "$kb" "$mb"
done

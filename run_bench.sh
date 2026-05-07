#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DATA="$ROOT/data/test.csv"

# ── helpers ──────────────────────────────────────────────────────────────────

header() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
ok()     { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
err()    { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; }

# ── 1. Generate data ──────────────────────────────────────────────────────────

header "Generating test data"
if [[ -f "$DATA" ]]; then
  echo "data/test.csv already exists, skipping generation."
else
  uv run --python 3.13 "$ROOT/generate_data.py"
fi

# ── 2. Python ────────────────────────────────────────────────────────────────

header "Python (uv / CPython 3.13)"
uv run --python 3.13 "$ROOT/bench/python/bench.py"

# ── 3. Python + pandas ───────────────────────────────────────────────────────

header "Python + pandas (uv / CPython 3.13)"
uv run --python 3.13 --with pandas "$ROOT/bench/python_pandas/bench.py"

# ── 3b. Python + Polars ──────────────────────────────────────────────────────

header "Python + Polars (uv / CPython 3.13)"
(cd "$ROOT/bench/python_polars" && uv run bench.py "$DATA")

# ── 4. JavaScript ────────────────────────────────────────────────────────────

header "JavaScript (Node.js $(node --version))"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck source=/dev/null
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
nvm use node --silent
node "$ROOT/bench/js/bench.mjs"

# ── 4b. JavaScript + csv-parse ───────────────────────────────────────────────

header "JavaScript + csv-parse (Node.js $(node --version))"
node "$ROOT/bench/js_csvparse/bench.mjs"

# ── 4c. JavaScript + PapaParse ───────────────────────────────────────────────

header "JavaScript + PapaParse (Node.js $(node --version))"
node "$ROOT/bench/js_papaparse/bench.mjs"

# ── 5. Go ────────────────────────────────────────────────────────────────────

header "Go ($(go version | awk '{print $3}'))"
go run "$ROOT/bench/go/bench.go"

# ── 6. Java ──────────────────────────────────────────────────────────────────

header "Java ($(java --version 2>&1 | head -1))"
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
JAVAC="$JAVA_HOME/bin/javac"
JAVA_BIN="$JAVA_HOME/bin/java"
JAVA_OUT="$ROOT/bench/java/out"
mkdir -p "$JAVA_OUT"
"$JAVAC" -d "$JAVA_OUT" "$ROOT/bench/java/BenchCSV.java"
"$JAVA_BIN" -cp "$JAVA_OUT" BenchCSV

# ── 6b. Java + univocity-parsers ─────────────────────────────────────────────

header "Java + univocity-parsers ($(java --version 2>&1 | head -1))"
JAVA_UNI_DIR="$ROOT/bench/java_univocity"
"$JAVAC" -cp "$JAVA_UNI_DIR/lib/univocity-parsers.jar" -d "$JAVA_UNI_DIR" "$JAVA_UNI_DIR/BenchUnivocity.java"
"$JAVA_BIN" -cp "$JAVA_UNI_DIR:$JAVA_UNI_DIR/lib/univocity-parsers.jar" BenchUnivocity "$DATA"

# ── 7. Ruby ──────────────────────────────────────────────────────────────────

header "Ruby (rbenv 3.4.8)"
export RBENV_ROOT="${RBENV_ROOT:-$HOME/.rbenv}"
export PATH="$RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH"
(
  cd "$ROOT/bench/ruby"
  rbenv local 3.4.8
  ruby "$ROOT/bench/ruby/bench.rb"
)

# ── 8. Ruby + SQLite (.import) ───────────────────────────────────────────────

header "Ruby + SQLite CLI .import (rbenv 3.4.8)"
(
  cd "$ROOT/bench/ruby_sqlite_import"
  rbenv local 3.4.8
  ruby "$ROOT/bench/ruby_sqlite_import/bench.rb"
)

# ── 9. Rust ──────────────────────────────────────────────────────────────────

header "Rust ($(source "$HOME/.cargo/env" && rustc --version | awk '{print $2}') --release)"
source "$HOME/.cargo/env"
cargo build --release --manifest-path "$ROOT/bench/rust/Cargo.toml" --quiet
"$ROOT/bench/rust/target/release/bench" "$DATA"

# ── 9b. Rust + csv crate ─────────────────────────────────────────────────────

header "Rust + csv crate (--release)"
cargo build --release --manifest-path "$ROOT/bench/rust_csv/Cargo.toml" --quiet
"$ROOT/bench/rust_csv/target/release/bench-csv-crate" "$DATA"

# ── 10. C++ ──────────────────────────────────────────────────────────────────

header "C++ (g++ $(g++ -dumpversion) -O2)"
g++ -O2 -std=c++20 -o "$ROOT/bench/cpp/bench" "$ROOT/bench/cpp/bench.cpp"
"$ROOT/bench/cpp/bench" "$DATA"

# ── 10. Bash + SQLite ────────────────────────────────────────────────────────

header "Bash + SQLite ($(sqlite3 --version | awk '{print $1}'))"
bash "$ROOT/bench/bash_sqlite/bench.sh" "$DATA"

# ── 11. Bash + DuckDB ────────────────────────────────────────────────────────

header "Bash + DuckDB ($(duckdb --version 2>/dev/null || ${DUCKDB_CLI:-/root/.duckdb/cli/latest/duckdb} --version))"
DUCKDB_CLI="${DUCKDB_CLI:-/root/.duckdb/cli/latest/duckdb}" bash "$ROOT/bench/bash_duckdb/bench.sh" "$DATA"

ok "All benchmarks complete."

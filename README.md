# CSV Benchmark

1,000,000行のCSVファイルを読み込み、カテゴリ別に集計するベンチマーク。

## CSV データ仕様

| カラム | 型 | 内容 |
|--------|-----|------|
| id | integer | 連番 (1〜1,000,000) |
| name | string | 氏名 |
| category | string | カテゴリ (10種類) |
| value | float | 単価 (1.00〜999.99) |
| quantity | integer | 数量 (1〜100) |
| date | string | 日付 (2024年内) |
| region | string | 地域 (5種類) |
| notes | string | **RFC 4180 の全エッジケースを網羅** |

`notes` 列には以下の値が混在し、ナイーブな実装（改行で行分割・カンマで列分割）が壊れることを確認できる。

| 種別 | 例 | 割合 |
|------|-----|------|
| 通常テキスト | `good` | 40% |
| カンマを含む | `"ships from Tokyo, Japan"` | 20% |
| ダブルクォートを含む | `"staff said ""excellent"""` | 20% |
| **改行を含む** | `"pros:\ngood quality\nfast"` | 20% |

物理行数は **1,266,058行**（CSVレコード数 1,000,000 + 改行埋め込み行 266,058）。ファイルサイズは約 **69MB**。

## 集計内容

`category` でグループ化し、以下を算出する。

- 行数 (count)
- 合計売上 `SUM(value × quantity)` (revenue)
- 平均単価 `AVG(value)` (avg_value)
- 最大・最小単価 (max / min)

## ベンチマーク結果

実行環境: Linux (WSL2) / 2026-05-07 / データ行数 1,000,000行

| # | 言語・実装 | バージョン | ライブラリ・手法 | 時間 |
|---|-----------|-----------|----------------|-----:|
| 1 | **Python + Polars** | CPython 3.13 / Polars 1.40 | `scan_csv` lazy API (SIMD + Arrow2) | **0.074s** |
| 2 | **Bash + DuckDB** | DuckDB v1.2.1 | `read_csv()` 直接クエリ (SIMD + vectorized) | **0.149s** |
| 3 | **Rust + csv crate** | rustc 1.95.0 `--release` | `csv` クレート (`memchr` SIMD スキャン) | **0.244s** |
| 4 | Go | go1.25.2 | 標準 `encoding/csv` (`bytes.IndexByte` AVX2) | **0.396s** |
| 5 | C++ | g++ 13.3 `-O2` | `fread` 64KB バッファ + RFC 4180 パーサー | **0.633s** |
| 6 | Ruby + SQLite (CLI import) | 3.4.8 / ActiveRecord 8.1.3 | `sqlite3` CLI `.import` + AR query | **0.661s** |
| 7 | Rust (手書き) | rustc 1.95.0 `--release` | `BufReader` 64KB + RFC 4180 パーサー | **0.694s** |
| 8 | **Java + univocity-parsers** | OpenJDK 21 | univocity-parsers 2.9.1 | **0.748s** |
| 9 | Python + pandas | CPython 3.13 (uv) | `read_csv(chunksize=50000)` + chunk `groupby` | **0.807s** |
| 10 | JavaScript (手書き) | Node.js v25.4.0 | `createReadStream` 64KB + RFC 4180 ステートマシン | **0.861s** |
| 11 | **JavaScript + PapaParse** | Node.js v25.4.0 | PapaParse 5 `step` コールバック | **1.320s** |
| 12 | Java (手書き) | OpenJDK 21 | `BufferedReader` + RFC 4180 文字単位パーサー | **1.595s** |
| 13 | Bash + SQLite | bash 5.2 / sqlite3 3.45.1 | `sqlite3` CLI `.import` + `printf` query | **1.869s** |
| 14 | Python | CPython 3.13 (uv) | 標準 `csv.DictReader` | **2.150s** |
| 15 | **JavaScript + csv-parse** | Node.js v25.4.0 | csv-parse 5 async iterator | **2.930s** |
| 16 | Ruby | 3.4.8 (rbenv) | 標準 `CSV.foreach` | **11.468s** |

> 各値は1回実行の計測時間。Java はJVM起動コストを含む。**太字**は後から追加した実装。

## メモリ使用量ランキング（ピーク RSS 小さい順）

計測方法: `/usr/bin/time -v` の "Maximum resident set size" (子プロセスを含む)

| # | 実装 | ピーク RSS | 備考 |
|---|------|----------:|------|
| 1 | Rust + csv crate | **2.2 MB** | 64KB バッファのみ。ランタイムなし |
| 2 | Rust (手書き) | **2.2 MB** | 同上 |
| 3 | C++ | **3.8 MB** | 64KB バッファのみ。ランタイムなし |
| 4 | Bash + SQLite | **8.1 MB** | SQLite はページ単位 B-tree。全体を展開しない |
| 5 | Ruby (stdlib CSV) | **13.4 MB** | インタープリタ起動のみ。CSVは1行ずつ処理 |
| 6 | Go | **19.3 MB** | Goランタイム + goroutineスタック分 |
| 7 | Python (stdlib csv) | **32.5 MB** | CPythonインタープリタ分 |
| 8 | JavaScript + csv-parse | **70.6 MB** | V8エンジン起動分 |
| 9 | JavaScript (手書き) | **74.8 MB** | 同上 |
| 10 | Python + pandas | **88.7 MB** | chunksize=50000 で常に50,000行分保持 |
| 11 | JavaScript + PapaParse | **90.7 MB** | 同上 |
| 12 | Bash + DuckDB | **103.4 MB** | vectorized 集計のための列バッファ |
| 13 | Ruby + SQLite (CLI import) | **121.0 MB** | ActiveRecord + sqlite3 gem + CLI プロセス |
| 14 | Java (手書き) | **203.4 MB** | JVMヒープのデフォルト割り当て（実使用は少ない） |
| 15 | Python + Polars | **212.1 MB** | Arrow2 columnar バッファ（全列をメモリに展開） |
| 16 | Java + univocity-parsers | **225.1 MB** | 同上（JVMヒープ） |

### 速度 vs メモリのトレードオフ

「標準モジュールのみ」= 言語処理系に同梱されているモジュールだけで実装できるか（外部ライブラリ・CLI ツール不要）。

| 実装 | 速度順位 | メモリ順位 | 標準モジュールのみ | 傾向 |
|------|:--------:|:---------:|:----------------:|------|
| Rust (手書き) | 7位 | **2位** | ✅ | メモリ最小級・外部依存なし |
| Rust + csv crate | 3位 | **1位** | ❌ `csv` クレート | 速くてメモリも最小だが外部依存あり |
| C++ | 5位 | **3位** | ✅ | 速くてメモリ小・外部依存なし |
| Go | 4位 | 6位 | ✅ | 速い・メモリ中程度・外部依存なし |
| JavaScript (手書き) | 10位 | 9位 | ✅ | Node.js 組み込みのみ |
| Java (手書き) | 12位 | 14位 | ✅ | 外部依存なしだが JVM ヒープが大きい |
| Python (stdlib csv) | 14位 | 7位 | ✅ | 遅いがシンプル |
| Ruby (stdlib CSV) | 16位 | 5位 | ✅ | 最遅だがメモリ少・外部依存なし |
| Python + Polars | **1位** | 15位 | ❌ `polars` | 最速だがメモリ大・要インストール |
| Bash + DuckDB | **2位** | 12位 | ❌ DuckDB CLI | 速いが CLI 要インストール |
| Java + univocity-parsers | 8位 | 16位 | ❌ JAR | 手書きより速いが JVM + JAR 分大きい |
| Python + pandas | 9位 | 10位 | ❌ `pandas` | 標準より速いが要インストール |
| JavaScript + PapaParse | 11位 | 11位 | ❌ npm | 手書きより遅い |
| JavaScript + csv-parse | 15位 | 8位 | ❌ npm | 手書きより遅い |
| Ruby + SQLite (CLI import) | 6位 | 13位 | ❌ gem + CLI | 速いが依存多い |
| Bash + SQLite | 13位 | **4位** | ❌ SQLite CLI | 遅いがメモリ極小 |

**標準モジュールのみで高速・省メモリを両立できる実装は Go・C++・Rust（手書き）の3つ。** これらは外部依存ゼロで上位に入っており、環境構築コストと性能のバランスが最もよい。

**SIMD/vectorized 系は速さとメモリの両立が難しい**: Polars と DuckDB は SIMD 集計のために列データをメモリに展開する必要があるため、ストリーム処理系より大幅にメモリを使う。**メモリ制約が厳しい環境では Rust / C++ / Go が最良の選択**。

## パーサーの実装方針

| 言語・実装 | 手法 | RFC 4180 対応 | SIMD 最適化 |
|-----------|------|:---:|:---:|
| Python | 標準 `csv.DictReader`（C実装） | ✅ 元から対応 | ❌ |
| Python + pandas | `pd.read_csv`（C実装） | ✅ 元から対応 | ❌ |
| **Python + Polars** | **`scan_csv` lazy API（Rust製 Arrow2 エンジン）** | ✅ | ✅ `memchr` AVX2 |
| Go | 標準 `encoding/csv` | ✅ 元から対応 | ✅ `bytes.IndexByte` AVX2 |
| Ruby | 標準 `CSV.foreach` | ✅ 元から対応 | ❌ |
| Ruby + SQLite | sqlite3 CLI `.import` | ✅ | ❌ |
| JavaScript (手書き) | `createReadStream` 64KB + RFC 4180 ステートマシン | ✅ 自前実装 | ❌ |
| **JavaScript + csv-parse** | **async iterator ストリーム** | ✅ | ❌ |
| **JavaScript + PapaParse** | **`step` コールバックストリーム** | ✅ | ❌ |
| Java (手書き) | `BufferedReader` + 文字単位 RFC 4180 パーサー | ✅ 自前実装 | ❌ |
| **Java + univocity-parsers** | **バッファ再利用・アロケーション最小化** | ✅ | ❌ |
| C++ | `fread` 64KB バッファ + RFC 4180 パーサー | ✅ 自前実装 | ❌ |
| Rust (手書き) | `BufReader::with_capacity(65536)` + RFC 4180 パーサー | ✅ 自前実装 | ❌ |
| **Rust + csv crate** | **`csv::ReaderBuilder` + `memchr` SIMD スキャン** | ✅ | ✅ `memchr` AVX2 |
| **Bash + DuckDB** | **`read_csv()` 直接クエリ (SIMD + vectorized 集計)** | ✅ | ✅ vectorized |
| Bash + SQLite | sqlite3 CLI `.import` + SQL query | ✅ | ❌ |

JavaScript・Java・C++・Rust の手書き実装はいずれも標準ライブラリに RFC 4180 準拠の CSV パーサーがないため、
クォートフィールド・`""` エスケープ・フィールド内改行を正しく扱うパーサーをゼロから実装した。

C++ と Rust の手書き実装はどちらも 64KB バッファで読み込み、`peek()` で次バイトを先読みして `""` エスケープと閉じクォートを区別する同一方式を採用しているため、実行時間もほぼ同等になっている。

## 考察

### DuckDB vs SQLite（SQL エンジン同士の比較）

どちらも「プログラムを書かずに SQL で CSV を集計する」アプローチだが、速度は大きく異なる。

| 実装 | 時間 | 手法 |
|------|-----:|------|
| Bash + DuckDB | **0.149s** | `read_csv()` 直接クエリ・SIMD vectorized 集計 |
| Ruby + SQLite (CLI import) | **0.661s** | `.import` でDBに取り込み → SQL クエリ |
| Bash + SQLite | **1.869s** | 同上（Ruby/AR なし） |

DuckDB は SQLite の **12倍速い**。SQLite は行指向エンジンで `.import` 後に B-tree スキャンを行うのに対し、DuckDB は列指向 OLAP エンジンで CSV を直接ベクトル化して処理する。インポート不要で CSV をそのまま `FROM read_csv(...)` で集計できる。

### ライブラリ実装 vs 手書き実装の比較

| 言語 | 手書き実装 | ライブラリ実装 | 差 |
|------|----------:|-------------:|---:|
| Rust | 0.694s | 0.244s (csv crate) | **2.8倍速い** |
| Java | 1.595s | 0.748s (univocity) | **2.1倍速い** |
| JavaScript | 0.861s | 1.320s (PapaParse) / 2.930s (csv-parse) | ライブラリが遅い |
| Python | 2.150s | 0.807s (pandas) / **0.074s (Polars)** | **29倍速い** |

Rust と Java では専用ライブラリが手書き実装を大幅に上回る。JavaScript は逆転しており、手書きステートマシンが既存ライブラリより速い（V8 JIT の特性上、シンプルなループがライブラリのオーバーヘッドより有利になる）。

### SIMD 最適化の効果

SIMD を活用する実装（Polars・DuckDB・Rust csv crate・Go）は軒並み上位に集中している。

**Python + Polars** (0.074s) は SIMD CSV パース + Apache Arrow2 columnar `group_by` が全て Rust で一体化。**DuckDB** (0.149s) も同様に SIMD ベクトル化処理だが、SQL エンジンの汎用性のために Polars より若干遅い。**Rust + csv crate** (0.244s) は `memchr` AVX2 スキャンのみで集計は通常の Rust ループ。**Go** (0.396s) は `bytes.IndexByte` AVX2 で区切り文字スキャンを高速化。

### 各実装のまとめ

**Python + Polars**: 最速。SIMD CSV パース + Arrow2 columnar `group_by` の相乗効果。`scan_csv` は lazy API で実際には内部でバッチ処理するがファイルを全てメモリに展開しない。

**Bash + DuckDB**: 第2位。SQL を1行書くだけで CSV ファイルを直接クエリできる最もシンプルな高速実装。インポート不要・スキーマ定義不要（`read_csv_auto` も使用可能）。

**Rust + csv crate**: `memchr` の SIMD スキャンが効いており、`csv` クレートは Rust エコシステムで事実上の標準。手書き Rust の約3倍速。

**Go**: `encoding/csv` が標準ライブラリとして SIMD 最適化済み（AVX2 `bytes.IndexByte`）。依存なし・ゼロ設定で高速。

**Java + univocity-parsers**: 手書き Java の2倍速。バッファ再利用・アロケーション最小化により GC プレッシャーを下げた設計。JVM 起動コスト（〜150ms）込みでも 0.75s。

**PapaParse vs csv-parse**: PapaParse の方が速い。PapaParse はコールバック方式で行単位に同期処理、csv-parse は async iterator で非同期変換オーバーヘッドが大きい。どちらも手書き実装より遅い。

**Ruby + SQLite (CLI import)**: Go に近い速度。sqlite3 CLI の `.import` が C パーサーで直接取り込むため Ruby ループなし。

**C++ / Rust (手書き)**: ともに 0.63〜0.69s で横並び。SIMD なし手書きパーサーの性能限界に収束している。

**Ruby (標準 CSV)**: 16実装中最遅。`CSV.foreach` の Ruby 層オーバーヘッドが支配的。コードは最も簡潔。

## ファイル構成

```
csvbench/
├── generate_data.py                   # テストデータ生成 (Python / uv)
├── data/test.csv                      # 1,000,000行テストデータ（物理行数 1,266,058 / 約69MB）
├── run_bench.sh                       # 全言語一括実行スクリプト
└── bench/
    ├── python/bench.py                # Python 標準 csv
    ├── python_pandas/bench.py         # Python + pandas
    ├── python_polars/bench.py         # Python + Polars (scan_csv lazy API)
    ├── js/bench.mjs                   # JavaScript (手書き RFC 4180 ステートマシン)
    ├── js_csvparse/bench.mjs          # JavaScript + csv-parse
    ├── js_papaparse/bench.mjs         # JavaScript + PapaParse
    ├── go/bench.go                    # Go (encoding/csv)
    ├── java/BenchCSV.java             # Java (手書き RFC 4180 文字単位パーサー)
    ├── java_univocity/BenchUnivocity.java  # Java + univocity-parsers
    ├── ruby/bench.rb                  # Ruby 標準 CSV
    ├── ruby_sqlite_import/bench.rb    # Ruby + SQLite + ActiveRecord (CLI import)
    ├── cpp/bench.cpp                  # C++ (fread 64KB バッファ + RFC 4180 パーサー)
    ├── rust/src/main.rs               # Rust (手書き BufReader 64KB + RFC 4180 パーサー)
    ├── rust_csv/src/main.rs           # Rust + csv crate
    ├── bash_sqlite/bench.sh           # Bash + SQLite (CLI .import + printf query)
    └── bash_duckdb/bench.sh           # Bash + DuckDB (read_csv 直接クエリ)
```

## 実行方法

```bash
# テストデータ生成 + 全ベンチマーク実行
bash run_bench.sh

# 個別実行例
uv run --python 3.13 bench/python/bench.py
uv run --python 3.13 --with pandas bench/python_pandas/bench.py
(cd bench/python_polars && uv run bench.py ../../data/test.csv)
node bench/js/bench.mjs
node bench/js_csvparse/bench.mjs
node bench/js_papaparse/bench.mjs
go run bench/go/bench.go
javac -d bench/java/out bench/java/BenchCSV.java && java -cp bench/java/out BenchCSV
javac -cp bench/java_univocity/lib/univocity-parsers.jar -d bench/java_univocity bench/java_univocity/BenchUnivocity.java
java -cp bench/java_univocity:bench/java_univocity/lib/univocity-parsers.jar BenchUnivocity data/test.csv
ruby bench/ruby/bench.rb
ruby bench/ruby_sqlite_import/bench.rb
g++ -O2 -std=c++20 -o bench/cpp/bench bench/cpp/bench.cpp && bench/cpp/bench data/test.csv
cargo build --release --manifest-path bench/rust/Cargo.toml && bench/rust/target/release/bench data/test.csv
cargo build --release --manifest-path bench/rust_csv/Cargo.toml && bench/rust_csv/target/release/bench-csv-crate data/test.csv
bash bench/bash_sqlite/bench.sh data/test.csv
DUCKDB_CLI=/root/.duckdb/cli/latest/duckdb bash bench/bash_duckdb/bench.sh data/test.csv
```

## 開発体験の比較

### 環境構築の手間

| 言語 | 必要だった準備作業 | 追加コマンド数 |
|------|-----------------|:------------:|
| Go | なし（go1.25.2 インストール済） | 0 |
| Python (csv) | なし（uv + Python 3.13 インストール済） | 0 |
| Python + pandas | なし（`--with pandas` フラグのみ、uv が自動解決） | 0 |
| JavaScript | なし（nvm + v25.4.0 インストール済） | 0 |
| C++ | なし（g++ 13 インストール済） | 0 |
| Ruby | `rbenv install 3.4.8`（バックグラウンド実行・数分） | 1 |
| Java | `apt install openjdk-21-jdk-headless`（JRE のみで javac なし） | 1 |
| Bash + SQLite | `apt install sqlite3` | 1 |
| Rust | `curl … \| sh`（rustup から全インストール・数分） | 1 |
| Ruby + SQLite | `gem install sqlite3`、`gem install activerecord`、`apt install sqlite3` | 3 |

### 実装中の主なエラー・手戻り

| 言語 | 発生した問題 | 原因 | 対処 |
|------|------------|------|------|
| Java | `javac: command not found` | JRE のみで JDK 未インストール | `apt install openjdk-21-jdk-headless` |
| Java | 集計結果が壊れる | `line.split(",")` でカンマ入り値を誤分割 | RFC 4180 文字単位パーサーに全面書き換え |
| JavaScript | 集計結果が壊れる | `readline` + `split(",")` → 同上 | RFC 4180 ステートマシンパーサーに全面書き換え |
| JavaScript | ストリーミング非対応 | `readFileSync` でファイル全読み込み | `createReadStream` + チャンク境界対応に再書き換え |
| Ruby + SQLite | `SyntaxError` | `def` 内で `class` を定義（Ruby では不可） | クラス定義をメソッド外に移動 |
| Ruby + SQLite | `no implicit conversion of nil` | `Tempfile#unlink` 後に `.path` が nil になる | `File.join(Dir.tmpdir, …)` に変更 |
| Bash + SQLite | 出力が折り返されて崩れる | `.mode column` が `printf()` 結果を再フォーマット | `.mode column` を削除 |
| C++ | `istream::get()` が遅い（Go の 3 倍以上） | 1 文字ずつのシステムコール相当のオーバーヘッド | `fread` 64KB バッファ読み込みクラスに書き換え |
| Rust | ビルド後にバイナリが見つからない | 相対パスで `cargo build` → ワーキングディレクトリがずれた | 絶対パス（`--manifest-path`）で再ビルド |

### コード規模（実装行数）

| 言語 | 行数 | 備考 |
|------|-----:|------|
| Ruby | 28 | 標準ライブラリが全部やってくれる |
| Bash + SQLite | 36 | SQL と CLI に処理を委譲 |
| Python + pandas | 42 | chunksize 対応で若干増 |
| Python (csv) | 44 | |
| Ruby + SQLite | 44 | |
| Go | 74 | 最も簡潔なネイティブ実装 |
| JavaScript | 83 | チャンク境界対応で膨らむ |
| Java | 95 | |
| C++ | 96 | |
| Rust | 98 | |

### まとめ

**手間がかからなかった言語**: Go・Python・C++
環境がそろっていて、標準ライブラリが正しく動いたか、コンパイラに渡すだけで動いた。

**環境構築で手間がかかった言語**: Ruby + SQLite（gem 3 個 + CLI ツール）・Rust（rustup インストール）・Java（JDK が入っていなかった）

**実装バグで手間がかかった言語**: **JavaScript と Java**
どちらも標準ライブラリに RFC 4180 パーサーがなく、最初に `split(",")` という誤った実装をしてしまい後から全面書き直しになった。この 2 言語だけでセッション全体の手戻りの大半を占める。C++ と Rust は同じく標準パーサーがないが、最初から正しい実装に着手できた。

## 動作要件

| ツール | 用途 |
|--------|------|
| uv | Python バージョン管理・実行 |
| nvm | Node.js バージョン管理 |
| rbenv + ruby-build | Ruby バージョン管理 |
| Go 1.25+ | Go 実行 |
| OpenJDK 21 (JDK) | Java コンパイル・実行 |
| sqlite3 CLI | Ruby + SQLite CLI import 版で使用 |
| activerecord gem | Ruby + SQLite 両版で使用 |
| Rust (rustup) | Rust 実行 |
| polars (pip) | Python + Polars (`uv sync` で自動インストール) |
| csv-parse (npm) | JavaScript + csv-parse (`npm install` 済) |
| papaparse (npm) | JavaScript + PapaParse (`npm install` 済) |
| univocity-parsers JAR | Java + univocity (`bench/java_univocity/lib/` に配置済) |
| DuckDB CLI | Bash + DuckDB (`~/.duckdb/cli/latest/duckdb`) |

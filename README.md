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
| 1 | **Python + Polars** | CPython 3.13 / Polars 1.40 | `scan_csv` lazy API (SIMD + Arrow2) | **0.084s** |
| 2 | **Rust + csv crate** | rustc 1.95.0 `--release` | `csv` クレート (`memchr` SIMD スキャン) | **0.236s** |
| 3 | Go | go1.25.2 | 標準 `encoding/csv` (`bytes.IndexByte` AVX2) | **0.396s** |
| 4 | C++ | g++ 13.3 `-O2` | `fread` 64KB バッファ + RFC 4180 パーサー | **0.642s** |
| 5 | Ruby + SQLite (CLI import) | 3.4.8 / ActiveRecord 8.1.3 | `sqlite3` CLI `.import` + AR query | **0.655s** |
| 6 | Rust (手書き) | rustc 1.95.0 `--release` | `BufReader` 64KB + RFC 4180 パーサー | **0.677s** |
| 7 | **Java + univocity-parsers** | OpenJDK 21 | univocity-parsers 2.9.1 | **0.731s** |
| 8 | Python + pandas | CPython 3.13 (uv) | `read_csv(chunksize=50000)` + chunk `groupby` | **0.876s** |
| 9 | JavaScript (手書き) | Node.js v25.4.0 | `createReadStream` 64KB + RFC 4180 ステートマシン | **0.909s** |
| 10 | **JavaScript + PapaParse** | Node.js v25.4.0 | PapaParse 5 `step` コールバック | **1.337s** |
| 11 | Java (手書き) | OpenJDK 21 | `BufferedReader` + RFC 4180 文字単位パーサー | **1.607s** |
| 12 | Bash + SQLite | bash 5.2 / sqlite3 3.45.1 | `sqlite3` CLI `.import` + `printf` query | **1.845s** |
| 13 | Python | CPython 3.13 (uv) | 標準 `csv.DictReader` | **2.235s** |
| 14 | **JavaScript + csv-parse** | Node.js v25.4.0 | csv-parse 5 async iterator | **2.922s** |
| 15 | Ruby | 3.4.8 (rbenv) | 標準 `CSV.foreach` | **11.978s** |

> 各値は1回実行の計測時間。Java はJVM起動コストを含む。**太字**は今回追加した実装。

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
| Bash + SQLite | sqlite3 CLI `.import` + SQL query | ✅ | ❌ |

JavaScript・Java・C++・Rust の手書き実装はいずれも標準ライブラリに RFC 4180 準拠の CSV パーサーがないため、
クォートフィールド・`""` エスケープ・フィールド内改行を正しく扱うパーサーをゼロから実装した。

C++ と Rust の手書き実装はどちらも 64KB バッファで読み込み、`peek()` で次バイトを先読みして `""` エスケープと閉じクォートを区別する同一方式を採用しているため、実行時間もほぼ同等になっている。

## 考察

### ライブラリ実装 vs 手書き実装の比較

| 言語 | 手書き実装 | ライブラリ実装 | 差 |
|------|----------:|-------------:|---:|
| Rust | 0.677s | 0.236s (csv crate) | **2.9倍速い** |
| Java | 1.607s | 0.731s (univocity) | **2.2倍速い** |
| JavaScript | 0.909s | 1.337s (PapaParse) / 2.922s (csv-parse) | ライブラリが遅い |
| Python | 2.235s | 0.876s (pandas) / **0.084s (Polars)** | **26倍速い** |

Rust と Java では専用ライブラリが手書き実装を大幅に上回る。JavaScript は逆転しており、手書きステートマシンが既存ライブラリより速い（V8 JIT の特性上、シンプルなループがライブラリのオーバーヘッドより有利になる）。

### SIMD 最適化の効果

**Python + Polars** (0.084s) と **Rust + csv crate** (0.236s) はいずれも `memchr` クレートを通じた AVX2 SIMD 命令でクォート・改行・カンマのバイトスキャンを行う。同じく AVX2 を使う Go の `encoding/csv` (0.396s) より Rust csv crate が速いのは、csv crate が SIMD スキャンを `csv-core` ステートマシンと直接統合しているため。

Polars が群を抜いて速い（Go の **4.7倍**）のは、SIMD CSV パース + Apache Arrow columnar 形式 + `group_by` の SIMD 集計が全て Rust で一体化しているため。

### 各実装のまとめ

**Python + Polars**: 断トツ最速。SIMD CSV パース + Arrow2 columnar `group_by` の相乗効果。`scan_csv` は lazy API で実際には内部でバッチ処理するがファイルを全てメモリに展開しない。

**Rust + csv crate**: 手書き Rust の約3倍速。`memchr` の SIMD スキャンが効いており、`csv` クレートは Rust エコシステムで事実上の標準。

**Go**: `encoding/csv` が標準ライブラリとして SIMD 最適化済み（AVX2 `bytes.IndexByte`）。依存なし・ゼロ設定で高速。

**Java + univocity-parsers**: 手書き Java の2倍速。バッファ再利用・アロケーション最小化により GC プレッシャーを下げた設計。JVM 起動コスト（〜150ms）込みでも 0.73s。

**PapaParse vs csv-parse**: PapaParse の方が速い。PapaParse はコールバック方式で行単位に同期処理、csv-parse は async iterator で非同期変換オーバーヘッドが大きい。どちらも手書き実装より遅い。

**Ruby + SQLite (CLI import)**: Go に近い速度。sqlite3 CLI の `.import` が C パーサーで直接取り込むため Ruby ループなし。

**C++ / Rust (手書き)**: ともに 0.64〜0.68s で横並び。SIMD なし手書きパーサーの性能限界に収束している。

**Ruby (標準 CSV)**: 15実装中最遅。`CSV.foreach` の Ruby 層オーバーヘッドが支配的。コードは最も簡潔。

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
    └── bash_sqlite/bench.sh           # Bash + SQLite (CLI .import + printf query)
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

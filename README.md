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
| 1 | Go | go1.25.2 | 標準 `encoding/csv` | **0.344s** |
| 2 | Ruby + SQLite (CLI import) | 3.4.8 / ActiveRecord 8.1.3 | `sqlite3` CLI `.import` + AR query | **0.635s** |
| 3 | C++ | g++ 13.3 `-O2` | `fread` 64KB バッファ + RFC 4180 パーサー | **0.636s** |
| 4 | Rust | rustc 1.95.0 `--release` | `BufReader` 64KB + RFC 4180 パーサー | **0.655s** |
| 5 | Python + pandas | CPython 3.13 (uv) | `read_csv(chunksize=50000)` + chunk `groupby` | **0.845s** |
| 6 | JavaScript | Node.js v25.4.0 | `createReadStream` 64KB + RFC 4180 ステートマシン | **0.900s** |
| 7 | Java | OpenJDK 21 | `BufferedReader` + RFC 4180 文字単位パーサー | **1.628s** |
| 8 | Bash + SQLite | bash 5.2 / sqlite3 3.45.1 | `sqlite3` CLI `.import` + `printf` query | **1.815s** |
| 9 | Python | CPython 3.13 (uv) | 標準 `csv.DictReader` | **2.284s** |
| 10 | Ruby | 3.4.8 (rbenv) | 標準 `CSV.foreach` | **11.433s** |

> 各値は1回実行の計測時間。Java はJVM起動コストを含む。

## パーサーの実装方針

| 言語 | 手法 | RFC 4180 対応 |
|------|------|:---:|
| Python | 標準 `csv.DictReader`（C実装） | ✅ 元から対応 |
| Python + pandas | `pd.read_csv`（C実装） | ✅ 元から対応 |
| Go | 標準 `encoding/csv` | ✅ 元から対応 |
| Ruby | 標準 `CSV.foreach` | ✅ 元から対応 |
| Ruby + SQLite | 標準 `CSV.foreach` / sqlite3 CLI | ✅ 元から対応 |
| **JavaScript** | **`createReadStream` 64KB チャンク + RFC 4180 ステートマシン** | ✅ 今回実装 |
| **Java** | **`BufferedReader` + 文字単位 RFC 4180 パーサー** | ✅ 今回実装 |
| **C++** | **`fread` 64KB バッファ + RFC 4180 パーサー** | ✅ 今回実装 |
| **Rust** | **`BufReader::with_capacity(65536)` + RFC 4180 パーサー** | ✅ 今回実装 |

JavaScript・Java・C++・Rust はいずれも標準ライブラリに RFC 4180 準拠の CSV パーサーがないため、
クォートフィールド・`""` エスケープ・フィールド内改行を正しく扱うパーサーをゼロから実装した。

C++ と Rust はどちらも `BufReader` / `fread` で 64KB ずつ読み込み、`peek()` で次バイトを先読みして `""` エスケープと閉じクォートを区別する同一方式を採用しているため、実行時間もほぼ同等になっている。

## 考察

**Go が最速**。`encoding/csv` は低オーバーヘッドで、ループ内演算もインライン展開されやすい。

**Ruby + SQLite (CLI import)** は Go に次ぐ速度。sqlite3 CLI の `.import` がCパーサーで直接CSVをDBに取り込むため、Rubyのループオーバーヘッドがゼロになる。ActiveRecord はクエリ部分のみ担当。

**Python + pandas** は純Pythonの `csv` モジュール比で約2.7倍速い。`read_csv` がCで実装されており、`groupby` も vectorized 演算のため効率的。

**JavaScript (Node.js)** は独自実装のステートマシンパーサーにもかかわらず Go の約3倍以内に収まる。V8 JIT による文字列操作最適化が効いている。

**C++ / Rust** はともに 64KB バッファ読み込み + 独自 RFC 4180 パーサーで 0.64〜0.66s と横並び。C++ は `fread` + `FILE*`、Rust は `BufReader::with_capacity` + `fill_buf` / `consume` という標準的なゼロコピーピーク API を使っており、生成されるコードの質も同等。

**Java** はJVM起動コスト（〜150ms）が支配的で、純粋な処理速度は他と同等以上と推測される。文字単位読み取りは `BufferedReader` がバッファリングするため実質的なI/Oコストは低い。

**Ruby (標準 CSV)** は `CSV.foreach` の実装コストにより他言語より遅いが、コードは最も簡潔。

**Bash + SQLite** は Ruby + SQLite (CLI import) と同じ sqlite3 CLI `.import` を使っているが、Ruby の ActiveRecord 起動コストがない分シンプル。ただし実測では Bash のプロセス起動・`date +%s%N` 計測オーバーヘッドもあり結果はほぼ同等。

## ファイル構成

```
csvbench/
├── generate_data.py                   # テストデータ生成 (Python / uv)
├── data/test.csv                      # 1,000,000行テストデータ（物理行数 1,266,058 / 約69MB）
├── run_bench.sh                       # 全言語一括実行スクリプト
└── bench/
    ├── python/bench.py                # Python 標準 csv
    ├── python_pandas/bench.py         # Python + pandas
    ├── js/bench.mjs                   # JavaScript (Node.js / RFC 4180 ステートマシン)
    ├── go/bench.go                    # Go
    ├── java/BenchCSV.java             # Java (RFC 4180 文字単位パーサー)
    ├── ruby/bench.rb                  # Ruby 標準 CSV
    ├── ruby_sqlite_import/bench.rb    # Ruby + SQLite + ActiveRecord (CLI import)
    ├── cpp/bench.cpp                  # C++ (fread 64KB バッファ + RFC 4180 パーサー)
    ├── rust/src/main.rs               # Rust (BufReader 64KB + RFC 4180 パーサー)
    └── bash_sqlite/bench.sh           # Bash + SQLite (CLI .import + printf query)
```

## 実行方法

```bash
# テストデータ生成 + 全ベンチマーク実行
bash run_bench.sh

# 個別実行例
uv run --python 3.13 bench/python/bench.py
uv run --python 3.13 --with pandas bench/python_pandas/bench.py
node bench/js/bench.mjs
go run bench/go/bench.go
javac -d bench/java/out bench/java/BenchCSV.java && java -cp bench/java/out BenchCSV
ruby bench/ruby/bench.rb
ruby bench/ruby_sqlite_import/bench.rb
g++ -O2 -std=c++20 -o bench/cpp/bench bench/cpp/bench.cpp && bench/cpp/bench
cargo build --release --manifest-path bench/rust/Cargo.toml && bench/rust/target/release/bench
bash bench/bash_sqlite/bench.sh
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

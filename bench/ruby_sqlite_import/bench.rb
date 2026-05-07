#!/usr/bin/env ruby
# Ruby + SQLite + ActiveRecord benchmark: bulk-import CSV via sqlite3 CLI, then aggregate with AR.

require "active_record"
require "tmpdir"

DATA_FILE = File.expand_path("../../data/test.csv", __dir__)

DB_FILE = File.join(Dir.tmpdir, "csvbench_#{Process.pid}.db")

# sqlite3 CLI: .import auto-creates the table from the CSV header
system("sqlite3", DB_FILE, ".mode csv", ".headers on", ".import #{DATA_FILE} sales",
       exception: true, out: File::NULL)

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB_FILE)

class Sale < ActiveRecord::Base; end

def run
  results = Sale
    .group(:category)
    .select("category",
            "COUNT(*) AS count",
            "SUM(value * quantity) AS revenue",
            "AVG(value) AS avg_value",
            "MAX(value) AS value_max",
            "MIN(value) AS value_min")
    .order(:category)

  printf "%-12s %8s %14s %12s %8s %8s\n", "Category", "Count", "Revenue", "Avg Value", "Max", "Min"
  puts "-" * 66
  results.each do |r|
    printf "%-12s %8d %14.2f %12.2f %8.2f %8.2f\n",
           r.category, r.count, r.revenue, r.avg_value, r.value_max, r.value_min
  end

end

start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
run
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
printf "\nElapsed: %.4fs\n", elapsed

ActiveRecord::Base.remove_connection
File.delete(DB_FILE) if File.exist?(DB_FILE)

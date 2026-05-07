#!/usr/bin/env ruby
# Ruby CSV benchmark: read 100k rows and aggregate by category.

require "csv"

DATA_FILE = File.expand_path("../../data/test.csv", __dir__)

def run
  totals = Hash.new do |h, k|
    h[k] = { revenue: 0.0, count: 0, value_sum: 0.0, value_max: -Float::INFINITY, value_min: Float::INFINITY }
  end

  CSV.foreach(DATA_FILE, headers: true) do |row|
    cat   = row["category"]
    value = row["value"].to_f
    qty   = row["quantity"].to_i
    g = totals[cat]
    g[:revenue]   += value * qty
    g[:count]     += 1
    g[:value_sum] += value
    g[:value_max]  = value if value > g[:value_max]
    g[:value_min]  = value if value < g[:value_min]
  end

  printf "%-12s %8s %14s %12s %8s %8s\n", "Category", "Count", "Revenue", "Avg Value", "Max", "Min"
  puts "-" * 66
  totals.keys.sort.each do |cat|
    g = totals[cat]
    avg = g[:value_sum] / g[:count]
    printf "%-12s %8d %14.2f %12.2f %8.2f %8.2f\n",
           cat, g[:count], g[:revenue], avg, g[:value_max], g[:value_min]
  end
end

start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
run
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
printf "\nElapsed: %.4fs\n", elapsed

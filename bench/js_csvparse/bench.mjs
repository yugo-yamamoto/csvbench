// JavaScript + csv-parse benchmark: streaming parse via async iterator.
import { parse } from "csv-parse";
import { createReadStream } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, dirname } from "node:path";

const DATA_FILE = join(dirname(fileURLToPath(import.meta.url)), "../../data/test.csv");

async function run() {
  const totals = new Map();

  const parser = createReadStream(DATA_FILE).pipe(
    parse({ columns: true, skip_empty_lines: true, relax_quotes: false })
  );

  for await (const rec of parser) {
    const cat   = rec.category;
    const value = parseFloat(rec.value);
    const qty   = parseInt(rec.quantity, 10);

    let g = totals.get(cat);
    if (!g) {
      g = { revenue: 0, count: 0, valueSum: 0, valueMax: -Infinity, valueMin: Infinity };
      totals.set(cat, g);
    }
    g.revenue  += value * qty;
    g.count    += 1;
    g.valueSum += value;
    if (value > g.valueMax) g.valueMax = value;
    if (value < g.valueMin) g.valueMin = value;
  }

  const cats = [...totals.keys()].sort();
  console.log(`${"Category".padEnd(12)} ${"Count".padStart(8)} ${"Revenue".padStart(14)} ${"Avg Value".padStart(12)} ${"Max".padStart(8)} ${"Min".padStart(8)}`);
  console.log("-".repeat(66));
  for (const cat of cats) {
    const g = totals.get(cat);
    const avg = g.valueSum / g.count;
    console.log(
      `${cat.padEnd(12)} ${g.count.toLocaleString().padStart(8)} ${g.revenue.toFixed(2).padStart(14)} ${avg.toFixed(2).padStart(12)} ${g.valueMax.toFixed(2).padStart(8)} ${g.valueMin.toFixed(2).padStart(8)}`
    );
  }
}

const start = performance.now();
await run();
const elapsed = (performance.now() - start) / 1000;
console.log(`\nElapsed: ${elapsed.toFixed(4)}s`);

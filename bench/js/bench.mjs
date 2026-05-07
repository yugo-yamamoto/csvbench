// JavaScript CSV benchmark: read 100k rows and aggregate by category.
// RFC 4180 compliant streaming parser — processes 64KB chunks from
// createReadStream without loading the whole file into memory.

import { createReadStream } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, dirname } from "node:path";

const DATA_FILE = join(dirname(fileURLToPath(import.meta.url)), "../../data/test.csv");

async function run() {
  const totals = new Map();
  let colIndex = null;

  // ── state machine variables ───────────────────────────────────────────────
  let inQuote = false;
  let field = "";
  let row = [];
  // A closing/escape quote that fell exactly on a chunk boundary is deferred
  // to the next chunk so we can peek at the following character.
  let deferredQuote = false;

  const processRow = (r) => {
    if (!colIndex) {
      colIndex = {};
      r.forEach((col, i) => { colIndex[col] = i; });
      return;
    }
    const cat   = r[colIndex["category"]];
    const value = parseFloat(r[colIndex["value"]]);
    const qty   = parseInt(r[colIndex["quantity"]], 10);
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
  };

  const stream = createReadStream(DATA_FILE, { encoding: "utf8", highWaterMark: 65536 });

  for await (const chunk of stream) {
    let i = 0;

    // Resolve a quote that was sitting at the end of the previous chunk.
    if (deferredQuote) {
      deferredQuote = false;
      if (chunk[0] === '"') {
        field += '"'; // was "" → escaped quote
        i = 1;
      } else {
        inQuote = false; // was closing quote; process chunk[0] normally below
      }
    }

    while (i < chunk.length) {
      const ch = chunk[i];
      if (inQuote) {
        if (ch === '"') {
          if (i + 1 < chunk.length) {
            if (chunk[i + 1] === '"') {
              field += '"'; i += 2; continue; // escaped ""
            } else {
              inQuote = false; // closing quote
            }
          } else {
            deferredQuote = true; i++; continue; // defer to next chunk
          }
        } else {
          field += ch; // includes embedded newlines
        }
      } else {
        if      (ch === '"')  { inQuote = true; }
        else if (ch === ',')  { row.push(field); field = ""; }
        else if (ch === '\n') { row.push(field); field = ""; processRow(row); row = []; }
        else if (ch !== '\r') { field += ch; }
      }
      i++;
    }
  }

  // Flush the last record if the file has no trailing newline.
  if (row.length > 0 || field !== "") {
    row.push(field);
    processRow(row);
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

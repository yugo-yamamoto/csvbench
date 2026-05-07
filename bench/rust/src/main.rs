use std::collections::BTreeMap;
use std::fs::File;
use std::io::{self, BufRead, BufReader, Read};
use std::path::PathBuf;
use std::time::Instant;

// ── Buffered RFC 4180 CSV parser ──────────────────────────────────────────────

struct CsvReader<R: Read> {
    inner: BufReader<R>,
}

impl<R: Read> CsvReader<R> {
    fn new(r: R) -> Self {
        Self { inner: BufReader::with_capacity(65536, r) }
    }

    /// Read one complete CSV record. Returns None at EOF.
    fn read_record(&mut self) -> io::Result<Option<Vec<String>>> {
        let mut fields: Vec<String> = Vec::new();
        let mut field = String::new();
        let mut in_quote = false;
        let mut any = false;

        loop {
            let mut byte = [0u8; 1];
            match self.inner.read(&mut byte) {
                Ok(0) => {
                    if any || !field.is_empty() {
                        fields.push(field);
                        return Ok(Some(fields));
                    }
                    return Ok(None);
                }
                Ok(_) => {}
                Err(e) => return Err(e),
            }
            any = true;
            let ch = byte[0] as char;

            if in_quote {
                if ch == '"' {
                    // Peek: "" is an escaped quote, otherwise it's the closing quote.
                    let next = self.inner.fill_buf()?;
                    if next.first() == Some(&b'"') {
                        self.inner.consume(1);
                        field.push('"');
                    } else {
                        in_quote = false;
                    }
                } else {
                    field.push(ch); // includes embedded newlines
                }
            } else {
                match ch {
                    '"'  => in_quote = true,
                    ','  => { fields.push(std::mem::take(&mut field)); }
                    '\n' => { fields.push(field); return Ok(Some(fields)); }
                    '\r' => {}
                    _    => field.push(ch),
                }
            }
        }
    }
}

// ── Aggregation ───────────────────────────────────────────────────────────────

#[derive(Default)]
struct Group {
    revenue:   f64,
    count:     u64,
    value_sum: f64,
    value_max: f64,
    value_min: f64,
}

fn main() -> io::Result<()> {
    let data_file = PathBuf::from(
        std::env::args().nth(1).unwrap_or_else(|| "../../data/test.csv".into()),
    );

    let file = File::open(&data_file)
        .unwrap_or_else(|e| panic!("cannot open {:?}: {}", data_file, e));

    let t0 = Instant::now();

    let mut reader = CsvReader::new(file);

    // Header
    let header = reader.read_record()?.expect("empty file");
    let col = |name: &str| header.iter().position(|h| h == name).expect(name);
    let cat_idx = col("category");
    let val_idx = col("value");
    let qty_idx = col("quantity");

    let mut totals: BTreeMap<String, Group> = BTreeMap::new();

    while let Some(row) = reader.read_record()? {
        let cat   = &row[cat_idx];
        let value: f64 = row[val_idx].parse().unwrap();
        let qty:   u64 = row[qty_idx].parse().unwrap();

        let g = totals.entry(cat.clone()).or_insert_with(|| Group {
            value_max: f64::NEG_INFINITY,
            value_min: f64::INFINITY,
            ..Default::default()
        });
        g.revenue   += value * qty as f64;
        g.count     += 1;
        g.value_sum += value;
        if value > g.value_max { g.value_max = value; }
        if value < g.value_min { g.value_min = value; }
    }

    println!("{:<12} {:>8} {:>14} {:>12} {:>8} {:>8}",
             "Category", "Count", "Revenue", "Avg Value", "Max", "Min");
    println!("{}", "-".repeat(66));
    for (cat, g) in &totals {
        let avg = g.value_sum / g.count as f64;
        println!("{:<12} {:>8} {:>14.2} {:>12.2} {:>8.2} {:>8.2}",
                 cat, g.count, g.revenue, avg, g.value_max, g.value_min);
    }

    println!("\nElapsed: {:.4}s", t0.elapsed().as_secs_f64());
    Ok(())
}

use std::collections::BTreeMap;
use std::env;
use std::error::Error;
use std::path::PathBuf;
use std::time::Instant;

fn main() -> Result<(), Box<dyn Error>> {
    let data_file = env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
            p.push("../../data/test.csv");
            p
        });

    let start = Instant::now();

    let mut rdr = csv::ReaderBuilder::new()
        .buffer_capacity(65536)
        .from_path(&data_file)?;

    let headers = rdr.headers()?.clone();
    let cat_idx = headers.iter().position(|h| h == "category").expect("category column");
    let val_idx = headers.iter().position(|h| h == "value").expect("value column");
    let qty_idx = headers.iter().position(|h| h == "quantity").expect("quantity column");

    struct Group {
        revenue: f64,
        count: u64,
        val_sum: f64,
        val_max: f64,
        val_min: f64,
    }

    let mut totals: BTreeMap<String, Group> = BTreeMap::new();

    for result in rdr.records() {
        let record = result?;
        let cat   = record[cat_idx].to_string();
        let value: f64 = record[val_idx].parse()?;
        let qty:   i64 = record[qty_idx].parse()?;

        let g = totals.entry(cat).or_insert(Group {
            revenue: 0.0,
            count: 0,
            val_sum: 0.0,
            val_max: f64::NEG_INFINITY,
            val_min: f64::INFINITY,
        });
        g.revenue += value * qty as f64;
        g.count   += 1;
        g.val_sum += value;
        if value > g.val_max { g.val_max = value; }
        if value < g.val_min { g.val_min = value; }
    }

    println!("{:<12} {:>8} {:>14} {:>12} {:>8} {:>8}",
        "Category", "Count", "Revenue", "Avg Value", "Max", "Min");
    println!("{}", "-".repeat(66));
    for (cat, g) in &totals {
        let avg = g.val_sum / g.count as f64;
        println!("{:<12} {:>8} {:>14.2} {:>12.2} {:>8.2} {:>8.2}",
            cat, g.count, g.revenue, avg, g.val_max, g.val_min);
    }

    let elapsed = start.elapsed().as_secs_f64();
    println!("\nElapsed: {:.4}s", elapsed);
    Ok(())
}

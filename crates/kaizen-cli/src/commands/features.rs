use anyhow::Result;
use kaizen_core::KaizenEngine;

use crate::output;

pub fn run(engine: &KaizenEngine) -> Result<()> {
    let names = engine.list_features()?;

    if names.is_empty() {
        println!("No features found. Check --features-dir.");
        return Ok(());
    }

    output::header("Available features");
    for name in &names {
        output::item(name);
    }
    println!();
    Ok(())
}

use kaizen_core::config::Config;

fn main() {
    let schema = schemars::schema_for!(Config);
    let output = serde_json::to_string_pretty(&schema).expect("serialize config schema");
    println!("{output}");
}

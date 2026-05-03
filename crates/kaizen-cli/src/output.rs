use owo_colors::OwoColorize;

pub fn header(title: &str) {
    println!("\n{}", title.bold());
    println!("{}", "─".repeat(42).dimmed());
}

pub fn kv(key: &str, value: &str) {
    println!("  {:<28} {}", key.cyan(), value);
}

pub fn item(text: &str) {
    println!("  {text}");
}

pub fn item_ok(text: &str) {
    println!("  {} {}", "✓".green(), text);
}

pub fn item_warn(text: &str) {
    println!("  {} {}", "⚠".yellow(), text);
}

pub fn item_err(text: &str) {
    println!("  {} {}", "✗".red(), text);
}

pub fn banner(os: &str) {
    println!("\n{}  ·  {}", "kaizen plan".bold().green(), os.dimmed());
    println!("{}", "═".repeat(44).dimmed());
}

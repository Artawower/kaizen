use owo_colors::OwoColorize;
use terminal_size::{terminal_size, Width};

fn term_width() -> usize {
    terminal_size()
        .map(|(Width(w), _)| w as usize)
        .unwrap_or(80)
}

pub fn page_header(title: &str) {
    println!("\n{}  {}", "kaizen".bold().green(), title);
    println!("{}", "═".repeat(term_width()).dimmed());
}

pub fn header(title: &str) {
    println!("\n{}", title.bold());
    println!("{}", "─".repeat(term_width()).dimmed());
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

pub fn feature_row(name: &str, enabled: bool, disabled_atoms: &[String]) {
    let marker = feature_marker(enabled);
    if disabled_atoms.is_empty() {
        println!("  {} {}", marker, name);
        return;
    }
    println!(
        "  {} {}  {}",
        marker,
        name,
        format!("[{} disabled]", disabled_atoms.join(", ")).dimmed()
    );
}

fn feature_marker(enabled: bool) -> String {
    if enabled {
        "●".green().to_string()
    } else {
        "○".dimmed().to_string()
    }
}

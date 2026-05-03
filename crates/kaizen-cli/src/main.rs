use anyhow::Result;
use clap::{Parser, Subcommand};
use tracing_subscriber::{fmt, EnvFilter};

mod commands;
mod output;

#[derive(Parser)]
#[command(name = "kaizen", about = "Headless workflow orchestrator", version)]
struct Cli {
    #[arg(
        long,
        global = true,
        env = "KAIZEN_FEATURES_DIR",
        default_value = "features"
    )]
    features_dir: std::path::PathBuf,

    #[arg(long, global = true)]
    config: Option<std::path::PathBuf>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Features,
    Plan {
        #[arg(long)]
        json: bool,
    },
    Doctor,
}

fn main() -> Result<()> {
    fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_target(false)
        .compact()
        .init();

    let cli = Cli::parse();
    let engine = kaizen_core::KaizenEngine::new(&cli.features_dir);
    let config_path = cli
        .config
        .unwrap_or_else(kaizen_core::KaizenEngine::default_config_path);

    match cli.command {
        Command::Features => commands::features::run(&engine)?,
        Command::Plan { json } => commands::plan::run(&engine, &config_path, json)?,
        Command::Doctor => commands::doctor::run(&engine, &config_path)?,
    }

    Ok(())
}

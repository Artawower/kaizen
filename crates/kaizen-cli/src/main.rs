use anyhow::Result;
use clap::{Parser, Subcommand};

mod commands;
mod ensure;
mod hooks;
mod output;
mod selector;

#[derive(Parser)]
#[command(
    name = "kaizen",
    about = "Headless workflow orchestrator — manage dotfiles, packages and dev tooling",
    version,
    arg_required_else_help = true
)]
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
    #[command(about = "Interactively configure kaizen and write config.toml")]
    Setup,

    #[command(about = "List available workflow features")]
    Features,

    #[command(about = "Build and display a workflow plan — no changes made")]
    Plan {
        #[arg(long, help = "Emit JSON instead of human-readable output")]
        json: bool,
    },

    #[command(about = "Install system packages from selected features via upt")]
    Install {
        #[arg(long, help = "Show what would be run without executing upt")]
        dry_run: bool,
    },

    #[command(about = "Remove selected packages via upt without changing kaizen config")]
    Uninstall {
        #[arg(long, help = "Show what would be run without executing upt")]
        dry_run: bool,
    },

    #[command(about = "Install packages and apply dotfiles in one step")]
    Sync {
        #[arg(long, help = "Preview without executing")]
        dry_run: bool,
    },

    #[command(about = "Write .chezmoidata.toml to the chezmoi source directory")]
    Apply {
        #[arg(
            long,
            help = "Preview changes without writing files or running chezmoi"
        )]
        dry_run: bool,
    },

    #[command(about = "Check system readiness and required tool availability")]
    Doctor,
}

fn main() -> Result<()> {
    colog::init();

    let cli = Cli::parse();
    let engine = kaizen_core::KaizenEngine::new(&cli.features_dir);
    let config_path = cli
        .config
        .unwrap_or_else(kaizen_core::KaizenEngine::default_config_path);

    match cli.command {
        Command::Setup => commands::setup::run(&engine, &config_path)?,
        Command::Features => commands::features::run(&engine)?,
        Command::Plan { json } => commands::plan::run(&engine, &config_path, json)?,
        Command::Install { dry_run } => commands::install::run(&engine, &config_path, dry_run)?,
        Command::Uninstall { dry_run } => commands::uninstall::run(&engine, &config_path, dry_run)?,
        Command::Sync { dry_run } => commands::sync::run(&engine, &config_path, dry_run)?,
        Command::Apply { dry_run } => commands::apply::run(&engine, &config_path, dry_run)?,
        Command::Doctor => commands::doctor::run(&engine, &config_path)?,
    }

    Ok(())
}

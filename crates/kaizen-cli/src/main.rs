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
    #[arg(long, global = true, env = "KAIZEN_FEATURES_DIR")]
    features_dir: Option<std::path::PathBuf>,

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

    #[command(about = "Install packages and apply dotfiles (auto-detects Nix or upt)")]
    Sync {
        #[arg(long, help = "Preview without executing")]
        dry_run: bool,
    },

    #[command(about = "Apply dotfiles via chezmoi + mise install")]
    Apply {
        #[arg(long, help = "Preview without writing files")]
        dry_run: bool,
    },

    #[command(about = "Upgrade packages, flake inputs and mise tools")]
    Update {
        #[arg(short = 'i', long, help = "Choose features interactively")]
        interactive: bool,

        #[arg(long, help = "Preview without making changes")]
        dry_run: bool,

        #[arg(long, help = "Run `nix flake update` before switching (Nix only)")]
        flake: bool,

        #[arg(help = "Feature names to update (default: all enabled)")]
        features: Vec<String>,
    },

    #[command(about = "Clean Nix store, OS package cache and Docker")]
    Clean {
        #[arg(long, help = "Preview without deleting anything")]
        dry_run: bool,
    },

    #[command(about = "Install system packages from selected features via upt")]
    Install {
        #[arg(long, help = "Show what would be run without executing")]
        dry_run: bool,
    },

    #[command(about = "Remove selected packages via upt")]
    Uninstall {
        #[arg(long, help = "Show what would be run without executing")]
        dry_run: bool,
    },

    #[command(about = "Check system readiness and tool availability")]
    Doctor,
}

fn main() -> Result<()> {
    colog::init();

    let cli = Cli::parse();
    let config_path = cli
        .config
        .unwrap_or_else(kaizen_core::KaizenEngine::default_config_path);

    if let Command::Setup = cli.command {
        return commands::setup::run(cli.features_dir.as_deref(), &config_path);
    }

    let features_dir = kaizen_core::resolve_features_dir(cli.features_dir)?;
    let engine = kaizen_core::KaizenEngine::new(&features_dir);

    match cli.command {
        Command::Setup => unreachable!(),
        Command::Features => commands::features::run(&engine)?,
        Command::Sync { dry_run } => commands::sync::run(&engine, &config_path, dry_run)?,
        Command::Apply { dry_run } => commands::apply::run(&engine, &config_path, dry_run)?,
        Command::Update {
            interactive,
            dry_run,
            flake,
            features,
        } => commands::update::run(&engine, &config_path, dry_run, flake, features, interactive)?,
        Command::Clean { dry_run } => commands::clean::run(&engine, &config_path, dry_run)?,
        Command::Install { dry_run } => commands::install::run(&engine, &config_path, dry_run)?,
        Command::Uninstall { dry_run } => commands::uninstall::run(&engine, &config_path, dry_run)?,
        Command::Doctor => commands::doctor::run(&engine, &config_path)?,
    }

    Ok(())
}

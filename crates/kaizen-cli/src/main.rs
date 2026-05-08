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
    /// First-time setup: run wizard then sync. Skips wizard if config already exists.
    Init {
        #[arg(long, help = "Preview sync without executing")]
        dry_run: bool,
    },

    /// Interactively configure kaizen and write config.toml.
    Setup,

    /// List available workflow features.
    Features,

    /// Install packages and apply dotfiles (auto-detects Nix or upt).
    Sync {
        #[arg(long, help = "Preview without executing")]
        dry_run: bool,
    },

    /// Apply dotfiles via chezmoi + mise install.
    Apply {
        #[arg(long, help = "Preview without writing files")]
        dry_run: bool,
    },

    /// Upgrade packages, flake inputs and mise tools.
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

    /// Clean Nix store, OS package cache and Docker.
    Clean {
        #[arg(long, help = "Preview without deleting anything")]
        dry_run: bool,
    },

    /// Explicitly install packages via upt (non-Nix systems only).
    /// On Nix systems use `kaizen sync` instead.
    Install {
        #[arg(long, help = "Show what would be run without executing")]
        dry_run: bool,
    },

    /// Remove packages (upt only). On Nix: disable features and run `kaizen sync`.
    Uninstall {
        #[arg(long, help = "Show what would be run without executing")]
        dry_run: bool,
    },

    /// Check system readiness and tool availability.
    Doctor,
}

fn main() -> Result<()> {
    colog::init();

    let cli = Cli::parse();
    let config_path = cli
        .config
        .unwrap_or_else(kaizen_core::KaizenEngine::default_config_path);

    if matches!(cli.command, Command::Setup | Command::Init { .. }) {
        let features_dir_path = cli.features_dir.clone();
        let features_dir_opt = features_dir_path.as_deref();
        return match cli.command {
            Command::Setup => commands::setup::run(features_dir_opt, &config_path),
            Command::Init { dry_run } => {
                let features_dir = kaizen_core::resolve_features_dir(cli.features_dir)?;
                let engine = kaizen_core::KaizenEngine::new(&features_dir);
                commands::init::run(&engine, features_dir_opt, &config_path, dry_run)
            }
            _ => unreachable!(),
        };
    }

    let features_dir = kaizen_core::resolve_features_dir(cli.features_dir)?;
    let engine = kaizen_core::KaizenEngine::new(&features_dir);

    match cli.command {
        Command::Setup | Command::Init { .. } => unreachable!(),
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
        Command::Install { dry_run } => {
            warn_if_nix_available();
            commands::install::run(&engine, &config_path, dry_run)?;
        }
        Command::Uninstall { dry_run } => {
            commands::uninstall::run(&engine, &config_path, dry_run)?;
        }
        Command::Doctor => commands::doctor::run(&engine, &config_path)?,
    }

    Ok(())
}

fn warn_if_nix_available() {
    if which::which("home-manager").is_ok() || which::which("darwin-rebuild").is_ok() {
        eprintln!(
            "warning: Nix detected — 'kaizen install' uses upt and will not update Nix packages.\n         Use 'kaizen sync' instead."
        );
    }
}

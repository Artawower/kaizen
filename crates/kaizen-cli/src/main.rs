use anyhow::Result;
use clap::{Parser, Subcommand};

mod backend;
mod chezmoi;
mod commands;
mod docker;
mod ensure;
mod executor;
mod filesystem;
mod hooks;
mod installer;
mod mise;
mod output;
mod paths;
mod reporter;
mod selector;

use std::sync::Arc;

use chezmoi::StdChezmoiClient;
use executor::StdProcessExecutor;
use filesystem::StdFileSystem;
use paths::StdPathProvider;
use reporter::StderrReporter;

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
    /// First-time machine install: configure if needed, then sync.
    Install {
        #[arg(long, help = "Preview sync without executing")]
        dry_run: bool,
    },

    /// Interactively configure kaizen: pick features, dotfiles URL, keyboard layout.
    Configure,

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

    /// Remove Kaizen-managed dotfiles, config, chezmoi source, and optionally Nix.
    Uninstall {
        #[arg(long, help = "Show what would be run without executing")]
        dry_run: bool,
    },

    /// Check system readiness and tool availability.
    Doctor,

    /// Upgrade tool versions and re-add lock/config files to the chezmoi source.
    /// Maintainer command: bumps mise + nix flake inputs, then re-adds locks to chezmoi.
    #[command(hide = true)]
    Bump {
        #[arg(long, help = "Update only nix flake inputs (default: all)")]
        nix: bool,
        #[arg(long, help = "Bump only mise tool versions (default: all)")]
        mise: bool,
        #[arg(long, help = "Preview without executing")]
        dry_run: bool,
    },
}

fn main() -> Result<()> {
    colog::init();

    let cli = Cli::parse();
    let config_path = cli
        .config
        .unwrap_or_else(|| kaizen_core::KaizenEngine::default_config_path(&StdPathProvider));

    let reporter = StderrReporter;

    if matches!(cli.command, Command::Configure | Command::Install { .. }) {
        let features_dir_path = cli.features_dir.clone();
        let features_dir_opt = features_dir_path.as_deref();
        return match cli.command {
            Command::Configure => commands::configure::run(features_dir_opt, &config_path),
            Command::Install { dry_run } => {
                let features_dir = kaizen_core::resolve_features_dir(
                    cli.features_dir,
                    &reporter,
                    &StdChezmoiClient,
                    &StdFileSystem,
                )?;
                let engine = kaizen_core::KaizenEngine::new(&features_dir, Arc::new(StdFileSystem));
                commands::install::run(&engine, features_dir_opt, &config_path, dry_run)
            }
            _ => unreachable!(),
        };
    }

    let features_dir = kaizen_core::resolve_features_dir(
        cli.features_dir,
        &reporter,
        &StdChezmoiClient,
        &StdFileSystem,
    )?;
    let engine = kaizen_core::KaizenEngine::new(&features_dir, Arc::new(StdFileSystem));

    match cli.command {
        Command::Configure | Command::Install { .. } => unreachable!(),
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
        Command::Uninstall { dry_run } => {
            commands::uninstall::run(&engine, &config_path, dry_run)?;
        }
        Command::Doctor => commands::doctor::run(&engine, &config_path)?,
        Command::Bump { nix, mise, dry_run } => {
            commands::bump::run(
                nix,
                mise,
                dry_run,
                &StdProcessExecutor,
                &StdPathProvider,
                &StderrReporter,
            )?;
        }
    }

    Ok(())
}

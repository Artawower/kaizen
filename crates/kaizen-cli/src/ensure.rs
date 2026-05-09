use anyhow::bail;
use owo_colors::OwoColorize;

use crate::output;

pub struct Tool {
    pub name: &'static str,
    pub install_hint: &'static str,
}

pub const UPT: Tool = Tool {
    name: "upt",
    install_hint: "https://github.com/sigoden/upt",
};

pub const CHEZMOI: Tool = Tool {
    name: "chezmoi",
    install_hint: "https://www.chezmoi.io/install/",
};

pub const MISE: Tool = Tool {
    name: "mise",
    install_hint: "https://mise.jdx.dev",
};

pub const HOME_MANAGER: Tool = Tool {
    name: "home-manager",
    install_hint: "https://nix-community.github.io/home-manager/",
};

pub const DARWIN_REBUILD: Tool = Tool {
    name: "darwin-rebuild",
    install_hint: "https://github.com/LnL7/nix-darwin",
};

pub const NIX: Tool = Tool {
    name: "nix",
    install_hint: "https://install.determinate.systems/nix",
};

/// Core tools required for kaizen to function.
pub const ALL: &[&Tool] = &[&UPT, &CHEZMOI, &MISE];

/// Nix-related tools checked by `kaizen doctor` when Nix backend is in use.
pub const NIX_TOOLS: &[&Tool] = &[&NIX, &HOME_MANAGER, &DARWIN_REBUILD];

pub fn require(tools: &[&Tool]) -> anyhow::Result<()> {
    let missing: Vec<&&Tool> = tools
        .iter()
        .filter(|t| which::which(t.name).is_err())
        .collect();

    if missing.is_empty() {
        return Ok(());
    }

    output::header("Missing required tools");
    for tool in &missing {
        output::item_err(&format!(
            "{:<12}  install at {}",
            tool.name,
            tool.install_hint.dimmed()
        ));
    }
    println!();
    bail!("{} required tool(s) not found", missing.len())
}

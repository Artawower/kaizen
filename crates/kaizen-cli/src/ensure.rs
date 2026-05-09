pub struct Tool {
    pub name: &'static str,
    pub install_hint: &'static str,
}

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
pub const ALL: &[&Tool] = &[&CHEZMOI, &MISE];

/// Nix-related tools checked by `kaizen doctor` when Nix backend is in use.
pub const NIX_TOOLS: &[&Tool] = &[&NIX, &HOME_MANAGER, &DARWIN_REBUILD];

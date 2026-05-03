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

pub const ALL: &[&Tool] = &[&UPT, &CHEZMOI, &MISE];

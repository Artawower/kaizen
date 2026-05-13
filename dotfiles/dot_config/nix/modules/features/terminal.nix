{ config, lib, pkgs, ... }:

let cfg = config.conf.features.terminal;
in

{
  options.conf.features.terminal.enable = lib.mkEnableOption "terminal, TUI tools, and shell";

  config = lib.mkMerge [
    {
      conf.featureRegistry.terminal = {
        description = "Terminal, TUI tools, and shell";
        category    = "terminal";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = with pkgs; [
        (import ../../pkgs/xonsh.nix { inherit pkgs; })
        bash-language-server
        zellij yazi tmux
        starship zoxide eza fastfetch direnv
        codebook
      ];
    })
  ];
}

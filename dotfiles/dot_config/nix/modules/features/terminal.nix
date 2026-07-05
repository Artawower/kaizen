{ pkgs, ... }:
{
  description = "Terminal, TUI tools, and shell";
  category = "terminal";
  packages = {
    nix = with pkgs; [
      (import ../../pkgs/xonsh.nix { inherit pkgs; })
      bash-language-server
      zellij
      yazi
      starship
      zoxide
      eza
      fastfetch
      direnv
      codebook
    ];
    darwin.casks = [
      "ghostty"
      "neohtop"
    ];
    darwin.taps = [ "muxy-app/tap" ];
  };
}

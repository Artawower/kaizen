{ pkgs, lib, ... }:
{
  description = "Core CLI utilities";
  category = "system";
  defaultEnable = true;

  packages = {
    nix = with pkgs; [
      ripgrep
      fd
      fzf
      jq
      tree
      curl
      wget
      unzip
      coreutils
      dash
      htop
      ncdu
      sqlite
      libpq
      just
      mise
      nil
      pandoc
      marksman
      yaml-language-server
      multimarkdown
      unrar
    ];
    darwin.brews = [ "mole" ];
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.conf.features.core;
in

{
  config = lib.mkIf cfg.enable {
    conf.packages.nix = with pkgs; [
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
      just
      mise

      nil
      pandoc
      marksman
      yaml-language-server

      multimarkdown
    ];
  };
}

{ config, lib, pkgs, ... }:

let
  cfg = config.conf.features.frontend;
in

{
  options.conf.features.frontend.enable = lib.mkEnableOption "frontend development tooling";

  config = lib.mkMerge [
    {
      conf.featureRegistry.frontend = {
        description = "Frontend development tooling";
        category    = "dev";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = with pkgs; [
        lua-language-server
        google-java-format
        mermaid-cli
      ];
    })
  ];
}

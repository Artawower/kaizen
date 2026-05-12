{ config, lib, pkgs, ... }:

let
  cfg     = config.conf.features.security;
  isLinux = pkgs.stdenv.isLinux;
in

{
  options.conf.features.security.enable = lib.mkEnableOption "security and privacy tools";

  config = lib.mkMerge [
    {
      conf.featureRegistry.security = {
        description = "Security and privacy: firewall, password manager, VPN, remote access";
        category    = "security";
      };
    }
    (lib.mkIf (cfg.enable && isLinux) {
      conf.packages.nix = with pkgs; [ bitwarden-cli ];
    })
  ];

  darwinCasks = [ "lulu" "bitwarden" "openvpn-connect" "amneziavpn" "rustdesk" ];
}

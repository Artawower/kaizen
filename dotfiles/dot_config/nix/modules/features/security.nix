{ pkgs, ... }:
{
  description = "Security and privacy: firewall, password manager, VPN, remote access";
  category    = "security";
  packages = {
    linux.nix = with pkgs; [ bitwarden-cli ];
    darwin.casks = [
      "lulu" "bitwarden" "openvpn-connect" "amneziavpn" "rustdesk"
    ];
  };
}

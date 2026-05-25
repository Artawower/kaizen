{ pkgs, ... }:
{
  description = "Frontend development tooling";
  category    = "dev";
  packages.nix = with pkgs; [
    lua-language-server
    google-java-format
    mermaid-cli
  ];
}

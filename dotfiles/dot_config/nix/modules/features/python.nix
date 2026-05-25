{ pkgs, ... }:
{
  description = "Python development tooling";
  category    = "dev";
  packages.nix = with pkgs; [ python3 uv ];
}

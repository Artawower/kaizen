{ pkgs, ... }:
{
  description = "Go development tooling";
  category    = "dev";
  packages.nix = with pkgs; [ go gopls go-tools ];
}

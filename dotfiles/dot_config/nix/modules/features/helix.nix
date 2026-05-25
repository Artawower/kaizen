{ pkgs, ... }:
{
  description = "Helix editor + marksman LSP";
  category    = "editor";
  packages.nix = with pkgs; [ helix marksman ];
}

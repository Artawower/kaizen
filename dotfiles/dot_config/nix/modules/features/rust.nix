{ pkgs, ... }:
{
  description = "Rust toolchain + cargo utilities";
  category    = "dev";
  packages.nix = with pkgs; [ gcc cmake llvmPackages.libclang ];
}

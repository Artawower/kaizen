{ ... }:

{
  imports = [
    ./options.nix
    ./feature-loader.nix
    ./adapters/home-manager.nix
    ./system/darkman.nix
  ];
}

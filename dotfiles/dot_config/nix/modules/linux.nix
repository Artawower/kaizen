{ ... }:

{
  imports = [
    ./options.nix
    ./feature-loader.nix
    ./adapters/home-manager.nix
    ./system/fonts.nix
    ./system/darkman.nix
    ./system/battery-thresholds.nix
  ];
}

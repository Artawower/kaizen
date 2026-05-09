{ config, lib, ... }:

{
  home.packages = lib.unique config.conf.packages.nix;
}

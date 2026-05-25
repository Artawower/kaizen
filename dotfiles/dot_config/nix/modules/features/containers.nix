{ pkgs, ... }:
{
  description = "Container and VM tooling: OrbStack";
  category    = "dev";
  packages = {
    linux.nix    = with pkgs; [ podman ];
    darwin.casks = [ "orbstack" ];
  };
}

{ lib, ... }:

{
  options.conf.features.nix-system.enable = lib.mkEnableOption "Nix flake inputs" // {
    default = true;
  };

  config = {
    conf.featureRegistry.nix-system = {
      description = "Nix flake inputs";
      category = "system";
      bump = {
        run = [
          {
            run = [
              "nix"
              "flake"
              "update"
              "--flake"
              "~/.config/nix"
            ];
            onFailure = "fail";
          }
        ];
        capture = [ "~/.config/nix/flake.lock" ];
      };
    };
  };
}

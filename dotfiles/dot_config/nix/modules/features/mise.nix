{ lib, ... }:

{
  options.conf.features.mise.enable = lib.mkEnableOption "Mise toolchains" // {
    default = true;
  };

  config = {
    conf.featureRegistry.mise = {
      description = "Mise toolchains";
      category = "dev";
      bump = {
        before = [
          {
            run = [
              "mise"
              "install"
            ];
            onFailure = "fail";
          }
        ];
        run = [
          {
            run = [ "~/.config/scripts/mise-bump" ];
            onFailure = "fail";
          }
        ];
        capture = [ "~/.config/mise.lock" ];
      };
    };
  };
}

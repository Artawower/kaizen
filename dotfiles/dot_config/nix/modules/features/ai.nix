{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.conf.features.ai;
in

{
  options.conf.features.ai.enable = lib.mkEnableOption "AI coding agents";

  config = lib.mkMerge [
    {
      conf.featureRegistry.ai = {
        description = "AI coding agents and tooling";
        category = "ai";
        update = [
          {
            run = [
              "pi"
              "update"
              "--extensions"
            ];
            onFailure = "warn";
          }
        ];
        bump = {
          before = [
            {
              run = [
                "pi"
                "update"
                "--extensions"
              ];
              onFailure = "warn";
            }
          ];
          run = [ ];
          capture = [ "~/.pi/agent/settings.json" ];
        };
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = with pkgs; [ podman ];
    })
  ];
}

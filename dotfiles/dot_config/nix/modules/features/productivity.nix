{ config, lib, pkgs, ... }:

let cfg = config.conf.features.productivity;
in

{
  options.conf.features.productivity.enable = lib.mkEnableOption "productivity tools";

  config = lib.mkMerge [
    {
      conf.featureRegistry.productivity = {
        description = "Productivity tools: notes, tasks, time-tracking, voice";
        category    = "productivity";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [
        "shottr"
        "chatgpt"
        "voiceink"
        "wakatime"
        "loom"
        "obsidian"
        "ticktick"
        "stretchly"
        "blankie"
      ];
    })
  ];
}

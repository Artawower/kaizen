{ config, lib, ... }:

let
  cfg = config.conf.features.productivity;
in

{
  options.conf.features.productivity.enable = lib.mkEnableOption "productivity tools";

  config = lib.mkMerge [
    {
      conf.featureRegistry.productivity = {
        description = "Productivity tools: notes, tasks, time-tracking, voice";
        category = "productivity";
      };
    }
  ];
}

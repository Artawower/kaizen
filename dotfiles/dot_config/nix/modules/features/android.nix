{ config, lib, ... }:

let cfg = config.conf.features.android;
in

{
  options.conf.features.android.enable = lib.mkEnableOption "Android development";

  config = lib.mkMerge [
    {
      conf.featureRegistry.android = {
        description = "Android development: Android Studio";
        category    = "dev";
      };
    }
  ];
}

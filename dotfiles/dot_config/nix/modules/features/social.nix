{ config, lib, ... }:

let cfg = config.conf.features.social;
in

{
  options.conf.features.social.enable = lib.mkEnableOption "social and communication apps";

  config = lib.mkMerge [
    {
      conf.featureRegistry.social = {
        description = "Social and communication: Discord, Telegram, Mattermost, WhatsApp";
        category    = "social";
      };
    }
  ];
}

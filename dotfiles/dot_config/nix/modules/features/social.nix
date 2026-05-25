{ config, lib, pkgs, ... }:

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
    (lib.mkIf cfg.enable {
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [
        "discord"
        "mattermost"
        "telegram-desktop"
        "whatsapp"
      ];
    })
  ];
}

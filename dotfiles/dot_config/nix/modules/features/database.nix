{ config, lib, pkgs, ... }:

let cfg = config.conf.features.database;
in

{
  options.conf.features.database.enable = lib.mkEnableOption "database GUI tools";

  config = lib.mkMerge [
    {
      conf.featureRegistry.database = {
        description = "Database GUI tools: SQLite Browser, MongoDB Compass";
        category    = "dev";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [
        "db-browser-for-sqlite"
        "mongodb-compass"
      ];
    })
  ];
}

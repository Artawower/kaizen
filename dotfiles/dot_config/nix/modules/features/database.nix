{ config, lib, ... }:

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
  ];

  darwinCasks = [ "db-browser-for-sqlite" "mongodb-compass" ];
}

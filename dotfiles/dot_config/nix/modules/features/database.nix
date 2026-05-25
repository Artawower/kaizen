{ ... }:
{
  description = "Database GUI tools: SQLite Browser, MongoDB Compass";
  category    = "dev";
  packages.darwin.casks = [ "db-browser-for-sqlite" "mongodb-compass" ];
}

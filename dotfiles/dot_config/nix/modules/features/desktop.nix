{ ... }:
{
  description = "Desktop utilities: launcher, menu bar, file manager, cleaner";
  category    = "desktop";
  packages.darwin.casks = [
    "raycast" "jordanbaird-ice" "stats" "clop" "marta" "pearcleaner"
  ];
}

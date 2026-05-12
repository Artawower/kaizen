# Battery charge thresholds are managed outside home-manager:
#   macOS  — AlDente (brew cask, already in darwin.nix)
#   Linux  — udev rules or kernel sysfs, not a home-manager concern
{ ... }: { }

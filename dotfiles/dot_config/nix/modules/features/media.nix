{ pkgs, ... }:
{
  description = "Media players: VLC, Spotube";
  category    = "media";
  packages = {
    linux.nix        = with pkgs; [ vlc ];
    darwin.casks     = [ "vlc" "krtirtho/apps/spotube" ];
    darwin.taps      = [ "krtirtho/apps" ];
  };
}

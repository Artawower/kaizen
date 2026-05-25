{ ... }:
{
  description   = "Nix flake inputs";
  category      = "system";
  defaultEnable = true;
  bump = {
    run     = [{ run = [ "nix" "flake" "update" "--flake" "~/.config/nix" ]; onFailure = "fail"; }];
    capture = [ "~/.config/nix/flake.lock" ];
  };
}

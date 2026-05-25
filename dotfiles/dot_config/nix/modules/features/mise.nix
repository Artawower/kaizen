{ ... }:
{
  description   = "Mise toolchains";
  category      = "dev";
  defaultEnable = true;
  bump = {
    before  = [{ run = [ "mise" "install" ]; onFailure = "fail"; }];
    run     = [{ run = [ "~/.config/scripts/mise-bump" ]; onFailure = "fail"; }];
    capture = [ "~/.config/mise.lock" ];
  };
}

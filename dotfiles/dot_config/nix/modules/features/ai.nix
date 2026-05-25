{ pkgs, lib, ... }:
{
  description = "AI coding agents and tooling";
  category    = "ai";

  packages = {
    nix          = with pkgs; [ podman ];
    darwin.casks = [ "claude-code" ];
  };

  update = [
    { run = [ "pi" "update" "--extensions" ]; onFailure = "warn"; }
  ];

  bump = {
    before  = [{ run = [ "pi" "update" "--extensions" ]; onFailure = "warn"; }];
    run     = [ ];
    capture = [ "~/.pi/agent/settings.json" ];
  };
}

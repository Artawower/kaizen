{
  lib,
  pkgs,
  user,
}:
let
  installer = ''
    target="/Applications/OmniWM.app"
    user_target="${user.homeDirectory}/Applications/OmniWM.app"
    if [ ! -d "$target" ] && [ ! -d "$user_target" ]; then
      if [ "$(uname -m)" != "arm64" ]; then
        echo "OmniWM requires Apple Silicon" >&2
        exit 1
      fi
      if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]; then
        echo "OmniWM requires macOS 26 or newer" >&2
        exit 1
      fi
      tmp_dir="$(mktemp -d)"
      trap 'rm -rf "$tmp_dir"' EXIT
      archive="$tmp_dir/OmniWM.zip"
      curl -fsSL "https://github.com/BarutSRB/OmniWM/releases/download/v0.5.6/OmniWM-v0.5.6.zip" -o "$archive"
      printf '%s  %s\n' "1a3365d625c21238c6314d7b17757725efdcddf4e2c23147c09cf3249703a3a5" "$archive" | shasum -a 256 -c -
      ditto -x -k "$archive" "$tmp_dir"
      mv "$tmp_dir/OmniWM.app" "$target"
    fi
  '';
in
{
  darwinTaps = [ ];
  darwinBrews = [ ];
  darwinCasks = [ ];
  darwinActivationScripts = {
    omniwmInstall = installer;
  };
}

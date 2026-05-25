{ pkgs, lib, user ? { username = "user"; }, ... }:
{
  description = "Emacs editor";
  category    = "editor";
  packages = {
    nix = with pkgs;
      [ imagemagick tree-sitter ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        emacs enchant_2 pkg-config isync msmtp cacert
      ];
    darwin.taps      = [ "d12frosted/emacs-plus" ];
    darwin.brewBundle = ''
      brew "d12frosted/emacs-plus/emacs-plus@31", args: ["with-xwidgets", "with-dbus"], build_from_source: true
    '';
  };
  activation.darwin = {
    emacsApp = ''
      emacs_src="/opt/homebrew/opt/emacs-plus@31/Emacs.app"
      emacs_dst="/Applications/Emacs.app"
      if [ -d "$emacs_src" ]; then
        if [ ! -d "$emacs_dst" ] || [ "$emacs_src/Contents/MacOS/Emacs" -nt "$emacs_dst/Contents/MacOS/Emacs" ]; then
          rm -rf "$emacs_dst"
          cp -r "$emacs_src" "$emacs_dst"
        fi
      fi
    '';
    ensureEmacsLogDir = ''
      su -l ${user.username} -c 'mkdir -p "$HOME/.local/state/emacs"'
    '';
    emacsClientApp = ''
      emacsclient_bin="/opt/homebrew/bin/emacsclient"
      target_dir="/Applications/Emacsclient.app"
      if [ -x "$emacsclient_bin" ]; then
        [ -d "$target_dir" ] && rm -rf "$target_dir"
        mkdir -p "$target_dir/Contents/MacOS" "$target_dir/Contents/Resources"
        cat > "$target_dir/Contents/Info.plist" <<'PLIST'
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>CFBundleDisplayName</key><string>Emacsclient</string>
        <key>CFBundleName</key><string>Emacsclient</string>
        <key>CFBundleIdentifier</key><string>org.gnu.emacsclient</string>
        <key>CFBundleVersion</key><string>1.0</string>
        <key>CFBundleShortVersionString</key><string>1.0</string>
        <key>CFBundleExecutable</key><string>Emacsclient</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>LSUIElement</key><false/>
      </dict></plist>
      PLIST
        cat > "$target_dir/Contents/MacOS/Emacsclient" <<'SCRIPT'
      #!/bin/sh
      exec /opt/homebrew/bin/emacsclient -c -a ""
      SCRIPT
        chmod +x "$target_dir/Contents/MacOS/Emacsclient"
      fi
    '';
  };
}

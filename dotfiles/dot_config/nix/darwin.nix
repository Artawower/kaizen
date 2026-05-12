{ self, user, lib, pkgs, ... }:

let
  dataPath = "${builtins.getEnv "HOME"}/.config/kaizen/data.toml";
  features =
    if builtins.pathExists dataPath
    then (builtins.fromTOML (builtins.readFile dataPath)).features or { }
    else { };
  f = name: features.${name} or false;
in

{
  environment.systemPackages = with pkgs; [
    vim
    nixfmt-rfc-style
  ];

  environment.variables = {
    EDITOR = "hx";
    PATH   = "${pkgs.coreutils}/bin:$PATH";
  };

  nix.enable = false;

  system.primaryUser = user.username;

  environment.shells = [ "/Users/${user.username}/.nix-profile/bin/xonsh" ];
  users.users.${user.username}.shell = "/Users/${user.username}/.nix-profile/bin/xonsh";

  system.defaults = {
    dock = {
      autohide      = true;
      tilesize      = 32;
      largesize     = 48;
      magnification = true;
      show-recents  = false;
    };
    loginwindow.LoginwindowText    = "Husky v maske";
    screencapture.location         = "~/Pictures/screenshots";
    screensaver.askForPasswordDelay = 30;
    CustomUserPreferences = {
      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys."61" = {
          enabled = true;
          value   = { parameters = [ 65535 105 0 ]; type = "standard"; };
        };
      };
    };
  };

  environment.loginItems = {
    enable = true;
    items = [
      "/Applications/Ice.app"
      "/Applications/AlDente.app"
      "/Applications/Stats.app"
      "/Applications/SpatialDock.app"
      "/Applications/VoiceInk.app"
      "/Applications/Input Source Pro.app"
      "/Applications/Raycast.app"
      "/Applications/Shottr.app"
      "/Applications/Clop.app"
    ];
  };

  system.activationScripts.setWorkspaceAutoSwoosh = ''
    echo "Disabling workspaces-auto-swoosh..."
    defaults write com.apple.dock workspaces-auto-swoosh -bool NO
    killall Dock || true
  '';

  system.activationScripts.setInputSourceHotkey = ''
    su -l ${user.username} -c 'killall SystemUIServer || true'
  '';

  system.activationScripts.disableLanguageCursorPopup = ''
    /usr/bin/defaults write /Library/Preferences/FeatureFlags/Domain/UIKit.plist redesigned_text_cursor -dict-add Enabled -bool NO
  '';

  system.activationScripts.postActivation.text = ''
    echo "Checking Library Validation..."
    if [ "$(/usr/bin/defaults read /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation 2>/dev/null)" != "1" ]; then
      /usr/bin/defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool YES
    fi

    emacsclient_bin="/opt/homebrew/bin/emacsclient"
    target_dir="/Applications/Emacsclient.app"
    if [ -x "$emacsclient_bin" ]; then
      [ -d "$target_dir" ] && rm -rf "$target_dir"
      mkdir -p "$target_dir/Contents/MacOS" "$target_dir/Contents/Resources"
      cat > "$target_dir/Contents/Info.plist" <<'EOF'
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
EOF
      cat > "$target_dir/Contents/MacOS/Emacsclient" <<'EOF'
#!/bin/sh
exec /opt/homebrew/bin/emacsclient -c -a ""
EOF
      chmod +x "$target_dir/Contents/MacOS/Emacsclient"
    fi
  '';

  system.activationScripts.ensureEmacsLogDir = ''
    su -l ${user.username} -c 'mkdir -p "$HOME/.local/state/emacs"'
  '';

  system.activationScripts.fixReadlink = ''
    if [ ! -f /usr/local/bin/readlink ]; then
      mkdir -p /usr/local/bin
      ln -sf ${pkgs.coreutils}/bin/readlink /usr/local/bin/readlink 2>/dev/null || true
    fi
  '';

  security.pam.services.sudo_local.touchIdAuth = true;

  security.sudo.extraConfig = ''
    ${user.username} ALL=(root) NOPASSWD: /opt/homebrew/bin/yabai --load-sa
  '';

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 5;
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.8" ];

  homebrew = {
    enable    = true;
    onActivation = { autoUpdate = true; cleanup = "uninstall"; upgrade = true; };

    taps = [
      "d12frosted/emacs-plus"
      "koekeishiya/formulae"
      "FelixKratz/formulae"
      "nikitabobko/tap"
      "krtirtho/apps"
      "Artawower/tap"
    ];

    brews =
      [ "chezmoi" "mas" "pkgconf" "enchant" "Artawower/tap/wallboy" "ntfy" ]
      ++ lib.optionals (f "tiling") [
        { name = "koekeishiya/formulae/yabai"; }
        { name = "koekeishiya/formulae/skhd"; }
        { name = "FelixKratz/formulae/borders"; restart_service = false; }
      ];

    casks = lib.unique (
      [
        "font-liga-comic-mono" "font-monaspace-nf"
        "orbstack"
        "lulu" "vlc" "marta" "pearcleaner"
        "krtirtho/apps/spotube" "discord"
        { name = "stretchly"; args.no_quarantine = true; }
        "obsidian" "neohtop" "db-browser-for-sqlite"
        "jordanbaird-ice" "zen" "loom"
        "clop" "input-source-pro"
        "mongodb-compass" "rustdesk" "wakatime"
        "arc" "openvpn-connect" "hoppscotch"
        "mattermost" "ticktick" "raycast" "licecap"
        "amneziavpn" "telegram-desktop" "bitwarden"
        "whatsapp" "keycastr" "stats" "zed"
        "chia" "aldente" "voiceink" "chatgpt"
        "claude-code" "android-studio" "cmux"
      ]
      ++ lib.optionals (f "terminal")  [ "ghostty" "wezterm" ]
      ++ lib.optionals (f "keyboard")  [ "karabiner-elements" ]
      ++ lib.optionals (f "tiling")    [ "nikitabobko/tap/aerospace" ]
    );

    extraConfig = lib.optionalString (f "emacs") ''
      brew "d12frosted/emacs-plus/emacs-plus@31", args: ["with-xwidgets", "with-dbus", "with-compress-install"], build_from_source: true
    '';

    masApps = { };
  };

  system.activationScripts.masOptional = ''
    if command -v mas >/dev/null 2>&1; then
      install_or_warn() {
        local name="$1" id="$2"
        echo "Installing optional MAS app: $name ($id)"
        mas install "$id" || echo "Warning: failed to install $name ($id)" >&2
      }
      install_or_warn "Arc browser" 6472513080
    else
      echo "mas not found; skipping optional MAS apps" >&2
    fi
  '';
}

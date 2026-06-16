{
  self,
  user,
  darwinSystem,
  lib,
  pkgs,
  ...
}:

let
  dataPath = "${user.homeDirectory}/.config/kaizen/data.toml";
  data = if builtins.pathExists dataPath then builtins.fromTOML (builtins.readFile dataPath) else { };
  extra = data.extra or { };

  userFeaturesPath = "${user.homeDirectory}/.config/kaizen/user-features";
  userDarwinFiles =
    if builtins.pathExists userFeaturesPath then
      builtins.filter (n: lib.hasSuffix ".darwin.nix" n) (
        builtins.attrNames (builtins.readDir userFeaturesPath)
      )
    else
      [ ];
  importUserDarwin = fileName: import (userFeaturesPath + "/${fileName}") { inherit lib pkgs user; };
  userLoaded = map importUserDarwin userDarwinFiles;

  userCasks = lib.concatMap (m: m.darwinCasks or [ ]) userLoaded;
  userBrews = lib.concatMap (m: m.darwinBrews or [ ]) userLoaded;
  userTaps = lib.concatMap (m: m.darwinTaps or [ ]) userLoaded;
  userFormulas = lib.concatStrings (map (m: m.darwinBrewFormulas or "") userLoaded);
  userActivation = lib.foldl' (acc: m: acc // (m.darwinActivationScripts or { })) { } userLoaded;

  darwinDepsPath = "${user.homeDirectory}/.config/kaizen/darwin-deps.json";
  darwinDeps =
    if builtins.pathExists darwinDepsPath then
      builtins.fromJSON (builtins.readFile darwinDepsPath)
    else
      {
        brews = [ ];
        casks = [ ];
        taps = [ ];
        brewFormulas = "";
        activationScripts = { };
      };
in

{
  environment.systemPackages = with pkgs; [
    vim
    nixfmt-rfc-style
    nixd
  ];

  environment.variables = {
    EDITOR = "hx";
    PATH = "${pkgs.coreutils}/bin:$PATH";
  };

  nix.enable = false;

  system.primaryUser = user.username;

  environment.shells = [ "/Users/${user.username}/.nix-profile/bin/xonsh" ];
  users.users.${user.username}.shell = "/Users/${user.username}/.nix-profile/bin/xonsh";

  system.defaults = {
    dock = {
      autohide = true;
      tilesize = 32;
      largesize = 48;
      magnification = true;
      show-recents = false;
    };
    loginwindow.LoginwindowText = "Husky v maske";
    screencapture.location = "~/Pictures/screenshots";
    screensaver.askForPasswordDelay = 30;
  };

  # Login items are managed manually via System Settings → General → Login Items.
  # The darwin-login-items module is removed: it uses Apple Events from root (sudo
  # darwin-rebuild) which macOS TCC blocks with errAEEventNotPermitted (-1743).

  system.activationScripts = lib.mkMerge [
    {
      setWorkspaceAutoSwoosh = ''
        echo "Disabling workspaces-auto-swoosh..."
        defaults write com.apple.dock workspaces-auto-swoosh -bool NO
        killall Dock || true
      '';
      disableLanguageCursorPopup = ''
        /usr/bin/defaults write /Library/Preferences/FeatureFlags/Domain/UIKit.plist redesigned_text_cursor -dict-add Enabled -bool NO
      '';
      postActivation.text = ''
        echo "Checking Library Validation..."
        if [ "$(/usr/bin/defaults read /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation 2>/dev/null)" != "1" ]; then
          /usr/bin/defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool YES
        fi
      '';
      fixReadlink = ''
        if [ ! -f /usr/local/bin/readlink ]; then
          mkdir -p /usr/local/bin
          ln -sf ${pkgs.coreutils}/bin/readlink /usr/local/bin/readlink 2>/dev/null || true
        fi
      '';
      masOptional = ''
        if command -v mas >/dev/null 2>&1; then
          install_or_warn() { local name="$1" id="$2"; mas install "$id" || echo "Warning: failed to install $name ($id)" >&2; }
          install_or_warn "Arc browser" 6472513080
        else
          echo "mas not found; skipping optional MAS apps" >&2
        fi
      '';
    }
    (lib.mapAttrs (_: text: { inherit text; }) (
      userActivation // (darwinDeps.activationScripts or { })
    ))
  ];

  security.pam.services.sudo_local.touchIdAuth = true;

  security.sudo.extraConfig = ''
    ${user.username} ALL=(root) NOPASSWD: /opt/homebrew/bin/yabai --load-sa
  '';

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 5;
  nixpkgs.hostPlatform = darwinSystem;
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.8" ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "none";
      upgrade = true;
    };

    taps = lib.unique (
      [ "Artawower/tap" ] ++ (extra.brew_taps or [ ]) ++ userTaps ++ (darwinDeps.taps or [ ])
    );

    brews = [
      "ca-certificates"
      "chezmoi"
      "mas"
      "pkgconf"
      "enchant"
      "Artawower/tap/wallboy"
      "ntfy"
    ]
    ++ (extra.brew_formulas or [ ])
    ++ userBrews
    ++ (darwinDeps.brews or [ ]);

    casks = lib.unique (
      [ "chia" ] ++ (extra.brew_casks or [ ]) ++ userCasks ++ (darwinDeps.casks or [ ])
    );

    extraConfig = userFormulas + (darwinDeps.brewFormulas or "");

    masApps = { };
  };

}

{
  self,
  user,
  lib,
  pkgs,
  ...
}:

let
  dataPath = "${user.homeDirectory}/.config/kaizen/data.toml";
  features =
    if builtins.pathExists dataPath then
      (builtins.fromTOML (builtins.readFile dataPath)).features or { }
    else
      { };
  f = name: features.${name} or false;

  featuresDir = ./modules/features;
  featureFiles = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (
    builtins.readDir featuresDir
  );

  # Import a feature file and read its darwin-specific top-level exports.
  # Nix laziness ensures home-manager-only attrs (options/config) are never
  # evaluated here — only the darwin export attrs are accessed.
  #
  # Feature files may declare:
  #   darwinCasks                :: list of (string | attrset)
  #   darwinBrews                :: list of (string | attrset)
  #   darwinTaps                 :: list of string
  #   darwinBrewFormulas         :: string  (appended to homebrew.extraConfig)
  #   darwinActivationScripts    :: attrset of name -> string
  importDarwin =
    fileName:
    let
      name = lib.removeSuffix ".nix" fileName;
    in
    if !(f name) then
      { }
    else
      import (featuresDir + "/${fileName}") {
        inherit lib pkgs user;
        config = { };
      };

  loaded = map importDarwin (builtins.attrNames featureFiles);

  featureCasks = lib.concatMap (m: m.darwinCasks or [ ]) loaded;
  featureBrews = lib.concatMap (m: m.darwinBrews or [ ]) loaded;
  featureTaps = lib.concatMap (m: m.darwinTaps or [ ]) loaded;
  featureFormulas = lib.concatStrings (map (m: m.darwinBrewFormulas or "") loaded);
  featureActivation = lib.foldl' (acc: m: acc // (m.darwinActivationScripts or { })) { } loaded;
in

{
  environment.systemPackages = with pkgs; [
    vim
    nixfmt-rfc-style
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
    (lib.mapAttrs (_: text: { inherit text; }) featureActivation)
  ];

  security.pam.services.sudo_local.touchIdAuth = true;

  security.sudo.extraConfig = ''
    ${user.username} ALL=(root) NOPASSWD: /opt/homebrew/bin/yabai --load-sa
  '';

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 5;
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.8" ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "uninstall";
      upgrade = true;
    };

    taps = lib.unique ([ "Artawower/tap" ] ++ featureTaps);

    brews = [
      "chezmoi"
      "mas"
      "pkgconf"
      "enchant"
      "Artawower/tap/wallboy"
      "ntfy"
    ]
    ++ featureBrews;

    casks = lib.unique ([ "chia" ] ++ featureCasks);

    extraConfig = featureFormulas;

    masApps = { };
  };

}

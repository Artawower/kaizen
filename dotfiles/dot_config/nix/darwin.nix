{
  self,
  user,
  lib,
  pkgs,
  ...
}:

let
  dataPath = "${user.homeDirectory}/.config/kaizen/data.toml";
  data = if builtins.pathExists dataPath then builtins.fromTOML (builtins.readFile dataPath) else { };
  features = data.features or { };
  extra = data.extra or { };
  f = name: features.${name} or false;

  featuresDir = ./modules/features;
  featureFiles = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".darwin.nix" n) (
    builtins.readDir featuresDir
  );

  importDarwin =
    fileName:
    let
      name = lib.removeSuffix ".darwin.nix" fileName;
    in
    if !(f name) then { } else import (featuresDir + "/${fileName}") { inherit lib pkgs user; };

  loaded = map importDarwin (builtins.attrNames featureFiles);

  featureCasks = lib.concatMap (m: m.darwinCasks or [ ]) loaded;
  featureBrews = lib.concatMap (m: m.darwinBrews or [ ]) loaded;
  featureTaps = lib.concatMap (m: m.darwinTaps or [ ]) loaded;
  featureFormulas = lib.concatStrings (map (m: m.darwinBrewFormulas or "") loaded);
  featureActivation = lib.foldl' (acc: m: acc // (m.darwinActivationScripts or { })) { } loaded;

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
    (lib.mapAttrs (_: text: { inherit text; }) (featureActivation // userActivation))
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

    taps = lib.unique ([ "Artawower/tap" ] ++ featureTaps ++ (extra.brew_taps or [ ]) ++ userTaps);

    brews = [
      "chezmoi"
      "mas"
      "pkgconf"
      "enchant"
      "Artawower/tap/wallboy"
      "ntfy"
    ]
    ++ featureBrews
    ++ (extra.brew_formulas or [ ])
    ++ userBrews;

    casks = lib.unique ([ "chia" ] ++ featureCasks ++ (extra.brew_casks or [ ]) ++ userCasks);

    extraConfig = featureFormulas + userFormulas;

    masApps = { };
  };

}

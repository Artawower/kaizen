{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.conf.features.keyboard;
  isDarwin = pkgs.stdenv.isDarwin;
in

{
  options.conf.features.keyboard = {
    enable = lib.mkEnableOption "keyboard layout tooling";

    nextInputSourceKey = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = {
        virtualKey = 105;
        charCode = 65535;
        modifiers = 0;
      };
      description = "Symbolic hotkey parameters for switching to next input source. null to leave unset.";
    };

    disableSpotlightHotkey = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable macOS Spotlight keyboard shortcuts Cmd+Space and Cmd+Opt+Space.";
    };
  };

  config = lib.mkMerge [
    {
      conf.featureRegistry.keyboard = {
        description = "Keyboard layout tooling";
        category = "system";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = lib.optionals (!isDarwin) (with pkgs; [ xremap ]);

      home.activation.configureInputSourceHotkeys = lib.mkIf isDarwin (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"

          /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:60:enabled false" "$plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:enabled bool false" "$plist"

          ${lib.optionalString cfg.disableSpotlightHotkey ''
            /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled false" "$plist" 2>/dev/null \
              || /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:64:enabled bool false" "$plist"
            /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:65:enabled false" "$plist" 2>/dev/null \
              || /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:65:enabled bool false" "$plist"
          ''}

          ${lib.optionalString (cfg.nextInputSourceKey != null) ''
            /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:61:enabled true"                                    "$plist" 2>/dev/null || true
            /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:61:value:parameters:0 ${toString cfg.nextInputSourceKey.charCode}"   "$plist" 2>/dev/null || true
            /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:61:value:parameters:1 ${toString cfg.nextInputSourceKey.virtualKey}" "$plist" 2>/dev/null || true
            /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:61:value:parameters:2 ${toString cfg.nextInputSourceKey.modifiers}"  "$plist" 2>/dev/null || true
          ''}

          /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
          killall cfprefsd 2>/dev/null || true
        ''
      );
    })
  ];
}

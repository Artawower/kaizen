{ pkgs, lib, ... }:
let
  nextInputSourceKey    = { virtualKey = 105; charCode = 65535; modifiers = 0; };
  disableSpotlightHotkey = true;
in
{
  description = "Keyboard layout tooling";
  category    = "system";
  packages = {
    linux.nix    = with pkgs; [ xremap ];
    darwin.casks = [ "karabiner-elements" "input-source-pro" ];
  };
  hmConfig = { isDarwin, lib, isLinux }:
    lib.optionalAttrs isDarwin {
      home.activation.configureInputSourceHotkeys =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
          /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:60:enabled false" "$plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:enabled bool false" "$plist"
          ${lib.optionalString disableSpotlightHotkey ''
            /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled false" "$plist" 2>/dev/null \
              || /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:64:enabled bool false" "$plist"
            /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:65:enabled false" "$plist" 2>/dev/null \
              || /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:65:enabled bool false" "$plist"
          ''}
          /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:61:enabled true" "$plist" 2>/dev/null || true
          /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:61:value:parameters:0 ${toString nextInputSourceKey.charCode}" "$plist" 2>/dev/null || true
          /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:61:value:parameters:1 ${toString nextInputSourceKey.virtualKey}" "$plist" 2>/dev/null || true
          /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:61:value:parameters:2 ${toString nextInputSourceKey.modifiers}" "$plist" 2>/dev/null || true
          /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
          killall cfprefsd 2>/dev/null || true
        '';
    };
}

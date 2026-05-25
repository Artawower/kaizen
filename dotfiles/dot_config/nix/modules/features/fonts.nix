{ pkgs, lib, ... }:
{
  description = "Fonts and Nerd Fonts";
  category    = "system";
  packages = {
    nix = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.caskaydia-cove
      nerd-fonts._3270
    ];
    darwin.casks = [ "font-liga-comic-mono" "font-monaspace-nf" ];
  };
  hmConfig = { isLinux, isDarwin, lib }:
    lib.optionalAttrs isLinux { fonts.fontconfig.enable = true; };
}

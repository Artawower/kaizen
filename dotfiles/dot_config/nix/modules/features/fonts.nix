{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.conf.features.fonts;
  isLinux = pkgs.stdenv.isLinux;
in

{
  options.conf.features.fonts.enable = lib.mkEnableOption "Fonts and Nerd Fonts";

  config = lib.mkMerge [
    {
      conf.featureRegistry.fonts = {
        description = "Fonts and Nerd Fonts";
        category = "system";
      };
    }
    (lib.mkIf cfg.enable {
      home.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        nerd-fonts.fira-code
        nerd-fonts.caskaydia-cove
        nerd-fonts._3270
      ];

      fonts.fontconfig.enable = lib.mkIf isLinux true;
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [
        "font-liga-comic-mono"
        "font-monaspace-nf"
      ];
    })
  ];
}

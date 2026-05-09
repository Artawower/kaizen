{ pkgs, ... }:

{
  home.packages = with pkgs; [
    darkman
    dconf
  ];

  xdg.configFile."darkman/config.yaml".text = ''
    usegeoclue: false
  '';

  xdg.dataFile."darkman/theme-switch.sh" = {
    text = ''
      #!/bin/sh
      MODE="$1"
      case "$MODE" in
        light)
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita'"
          ;;
        dark)
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"
          ;;
      esac
    '';
    executable = true;
  };

  xdg.configFile."xdg-desktop-portal/portals.conf".text = ''
    [preferred]
    default=gtk
  '';
}

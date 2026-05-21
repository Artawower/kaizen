; Example user overrides — copy to ~/.config/kaizen/user/ and adapt.
; Files in this directory are loaded after all preset feature modules.

; Override the keyboard layout (default is set by features/settings).
; (set-global! :layout "qwerty")

; Override a specific binding in a module.
; (rebind! 'helix :vcs/ui "space o o")

; Set a module-specific config value.
; (set-module-config! 'helix :leader ",")

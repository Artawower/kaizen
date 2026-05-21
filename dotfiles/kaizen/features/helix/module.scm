(declare-module "helix"
  :group 'editor
  :os '(darwin linux))

(nix! "helix")

(config-dir! ".")

;; Core actions
(define-action "open-yazi" "Open file in yazi")
(define-action "jjui-launch" "Launch jjui file picker")
(define-action "git-log" "Show git log")
(define-action "git-status" "Show git status")
(define-action "git-diff" "Show git diff")
(define-action "toggle-wrap" "Toggle soft-wrap")
(define-action "config-reload" "Reload config")

;; Normal mode bindings (base layer - works for both layouts)
(bind! "open-yazi" ".")
(bind! "jjui-launch" "o j")
(bind! "git-log" "g g")
(bind! "git-status" "g s")
(bind! "git-diff" "g d")
(bind! "toggle-wrap" "w v")
(bind! "config-reload" "h r")

;; Insert mode bindings
"space" = ["normal_mode" ":write"]

;; Select mode bindings (Colemak-aware)
(define (render-layout-bindings layout)
  (if (equal? layout "colemak")
      (hash
        "n" "move_visual_line_down"
        "e" "move_visual_line_up"
        "i" "move_char_right"
        "j" "search_next"
        "k" "move_next_word_end"
        "l" "insert_mode")
      (hash
        "j" "move_visual_line_down"
        "k" "move_visual_line_up"
        "l" "move_char_right"
        "h" "move_char_left"
        "i" "move_next_word_end")))

(on-apply!
  (lambda ()
    (let [(layout (get-context "layout"))]
      (generate-file!
        "~/.config/helix/config.toml"
        (string-append
          "[editor]\n"
          "line-number = \"relative\"\n"
          "gutters = [\"diagnostics\", \"spacer\", \"line-numbers\", \"diff\"]\n"
          "mouse = true\n"
          "shell = [\"/usr/bin/env\", \"xonsh\", \"-c\"]\n"
          "\n"
          "[editor.statusline]\n"
          "left = [\"mode\", \"spinner\", \"version-control\", \"spacer\", \"separator\", \"file-base-name\"]\n"
          "right = [\"diagnostics\", \"position\", \"file-encoding\", \"file-type\"]\n"
          "\n"
          "[keys.normal]\n"
          "\"C-.\" = \"rotate_view\"\n"
          "\"C-s\" = \":write\"\n"
          "\"F12\" = \":new\"\n"
          "\n"
          "[keys.normal.space]\n"
          "\".\" = \":sh yazi-picker\"\n"
          "\"o j\" = \":sh jjui-picker\"\n"
          "\"g g\" = \":sh git-log\"\n"
          "\"g s\" = \":sh git-status\"\n"
          "\"g d\" = \":sh git-diff\"\n"
          "\"w v\" = \":toggle soft-wrap.enable\"\n"
          "\"h r\" = \":config-reload\"\n"
          "\n"
          ;; Layout-specific bindings
          "[keys.normal \"g\"]\n"
          "\"d\" = \"goto_definition\"\n"
          "\"r\" = \"goto_reference\"\n"
          "\"i\" = \"goto_implementation\"\n"
          "\n"
          "[keys.insert]\n"
          "\"C-s\" = [\"normal_mode\", \":write\"]\n"
          "\n"
          (if (equal? layout "colemak")
              "[keys.select]\nn = \"extend_line_down\"\ne = \"extend_line_up\"\ni = \"extend_char_right\"\nj = \"search_next\"\n"
              "[keys.select]\nj = \"extend_line_down\"\nk = \"extend_line_up\"\nl = \"extend_char_right\"\n"))))))
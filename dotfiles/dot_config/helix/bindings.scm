(require "helix/keymaps.scm")
(require "tools.scm")
(require "vcs.scm")

(add-global-keybinding
  (hash
    "normal"
    (hash
      "X"
      (list "extend_line_up" "extend_to_line_bounds")
      "C-."
      "rotate_view"
      "C-s"
      ":write"
      "F12"
      terminal-actions
      "y"
      "yank_to_clipboard"
      "S-n"
      ":pipe-to sh -c 'printf \"%s:%s-%s\\n%s\" \"$(realpath \"$1\")\" \"$2\" \"$3\" \"$(cat)\" | pbcopy' sh \"%{buffer_name}\" \"%{selection_line_start}\" \"%{selection_line_end}\""
      "Y"
      "yank"
      "D"
      (list "ensure_selections_forward" "extend_to_line_end" "delete_selection")
      "0"
      "goto_line_start"
      "$"
      "goto_line_end"
      "^"
      "goto_first_nonwhitespace"
      "G"
      "goto_file_end"
      "V"
      (list "select_mode" "extend_to_line_bounds")
      "esc"
      (list "collapse_selection" "keep_primary_selection")
      "/"
      ":search-smart"
      "*"
      (list "move_prev_word_start" "move_next_word_end" "search_selection" "global_search")
      "A-["
      "goto_previous_buffer"
      "A-]"
      "goto_next_buffer"
      "g"
      (hash
        "d"
        "goto_definition"
        "D"
        (list ":buffer-close-others" "vsplit" "goto_definition")
        "R"
        (list ":buffer-close-others" "vsplit" "goto_reference")
        "r"
        "goto_reference"
        "i"
        "goto_implementation"
        "t"
        "goto_type_definition"
        "w"
        "goto_word")
      "space"
      (hash
        "."
        yazi-actions
        "y"
        "yank_to_clipboard"
        "p"
        "paste_clipboard_after"
        "q"
        ":buffer-close"
        "Q"
        ":quit-all"
        "/"
        "global_search"
        "["
        "goto_previous_buffer"
        "]"
        "goto_next_buffer"
        "e"
        "file_explorer"
        "o"
        (hash "f" ":forest-open" "F" ":forest-toggle" "j" jjui-actions)
        "b"
        (hash "b" "buffer_picker" "]" "goto_next_buffer" "[" "goto_previous_buffer" "q" ":buffer-close")
        "w"
        (hash "q" ":wclose"
          "v" "vsplit"
          "h"
          "hsplit"
          "r"
          "rotate_view"
          "l"
          (list ":toggle-option soft-wrap.enable" ":redraw"))
        "m"
        (hash "e" (hash "b" ":eval-buffer"))
        "f"
        (hash "f" "file_picker"
          "g"
          "global_search"
          "b"
          "buffer_picker"
          "s"
          "workspace_symbol_picker"
          "e"
          "file_explorer"
          "r"
          scooter-actions
          "d"
          yazi-actions)
        "v"
        (hash "l" gitu-actions
          "h"
          vcs-history-actions)
        "g"
        (hash "G" lazygit-actions
          "u"
          gitui-actions
          "s"
          (list ":new" ":insert-output git status" ":buffer-close!" ":redraw")
          "d"
          (list ":new" ":insert-output git diff" ":buffer-close!" ":redraw")
          "c"
          "toggle_comments"
          "f"
          "changed_file_picker"
          "r"
          ":reset-diff-change"
          "b"
          ":run-shell-command ~/.config/helix/utils/blame_line_pretty.sh %{buffer_name} %{cursor_line}"
          "B"
          ":open %sh{~/.config/helix/utils/blame_file_pretty.sh %{buffer_name} %{cursor_line}}"
          "h"
          ":run-shell-command ~/.config/helix/utils/git-hunk.sh %{buffer_name} %{cursor_line} 3")
        "h"
        (hash "r" (hash "k" ":config-reload"))
        "l"
        (hash "a" "code_action"
          "r"
          "rename_symbol"
          "f"
          "format_selections"
          "h"
          "hover"
          "s"
          "symbol_picker"
          "d"
          "diagnostics_picker")
        "c"
        (hash "n" ":sh basename %{buffer_name} | tr -d '\\n' | pbcopy"
          "p"
          ":sh echo -n %{buffer_name} | pbcopy")))
    "insert"
    (hash
      "C-s"
      (list "normal_mode" ":write")
      "C-."
      (list "normal_mode" "rotate_view")
      "C-g"
      gitui-actions)
    "select"
    (hash
      "/"
      ":search-smart"
      "C-c"
      "toggle_comments"
      "y"
      "yank_to_clipboard"
      "p"
      "paste_clipboard_after"
      "P"
      "paste_clipboard_before"
      "0"
      "goto_line_start"
      "$"
      "goto_line_end"
      "^"
      "goto_first_nonwhitespace"
      "G"
      "goto_file_end"
      "D"
      (list "extend_to_line_bounds" "delete_selection" "normal_mode"))))

(add-global-keybinding
  (hash
    "normal"
    (hash
      "C-j"
      "goto_next_diag"
      "C-k"
      "goto_prev_diag"
      "C-A-left"
      "jump_view_left"
      "C-A-right"
      "jump_view_right"
      "C-A-up"
      "jump_view_up"
      "C-A-down"
      "jump_view_down"
      "C-A-h"
      "jump_view_left"
      "C-A-l"
      "jump_view_right"
      "C-A-k"
      "jump_view_up"
      "C-A-j"
      "jump_view_down"
      "C-A-S-left"
      "swap_view_left"
      "C-A-S-right"
      "swap_view_right"
      "C-A-S-up"
      "swap_view_up"
      "C-A-S-down"
      "swap_view_down"
      "C-A-S-h"
      "swap_view_left"
      "C-A-S-l"
      "swap_view_right"
      "C-A-S-k"
      "swap_view_up"
      "C-A-S-j"
      "swap_view_down")))

(add-global-keybinding
    (hash
      "normal"
      (hash "K" "hover")
      "select"
      (hash "k" (list "extend_line_up" "extend_to_line_bounds")
        "j"
        (list "extend_line_down" "extend_to_line_bounds"))))

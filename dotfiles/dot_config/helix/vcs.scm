(define jjui-actions
  (list ":sh rm -f /tmp/jjui"
    ":insert-output [[ %{buffer_name} == \"[scratch]\" ]] && jjui %{current_working_directory} --chooser-file=/tmp/jjui-helix || jjui %{buffer_name} --chooser-file=/tmp/jjui-helix"
    ":insert-output echo \"\\x1b[?1049h\\x1b[?2004h\" > /dev/tty"
    ":open %sh{cat /tmp/jjui-helix}"
    ":redraw"
    ":set mouse false"
    ":set mouse true"))

(define gitu-actions
  (list ":write-all"
    ":insert-output gitu >/dev/tty"
    ":redraw"
    ":reload-all"))

(define lazygit-actions
  (list ":write-all"
    ":insert-output lazygit >/dev/tty"
    ":redraw"
    ":reload-all"))

(define gitui-actions
  (list ":write-all"
    ":new"
    ":insert-output gitui >/dev/tty"
    ":set mouse false"
    ":set mouse true"
    ":buffer-close!"
    ":redraw"
    ":reload-all"))

(define vcs-history-actions
  (list ":new"
    ":insert-output git log --follow --oneline -10 -- %{buffer_name}"
    ":buffer-close!"
    ":redraw"))

(provide jjui-actions)
(provide gitu-actions)
(provide lazygit-actions)
(provide gitui-actions)
(provide vcs-history-actions)

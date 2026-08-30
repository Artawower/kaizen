(define terminal-actions
  (list ":new" ":insert-output $SHELL" ":buffer-close!" ":redraw"))

(define yazi-actions
  (list ":sh rm -f /tmp/yazi-path"
    ":insert-output yazi %{buffer_name} --chooser-file=/tmp/yazi-path"
    ":open %sh{cat /tmp/yazi-path}"
    ":redraw"
    ":reload-all"
    ":set mouse false"
    ":set mouse true"))

(define scooter-actions
  (list ":write-all"
    ":insert-output scooter >/dev/tty"
    ":redraw"
    ":reload-all"))

(provide terminal-actions)
(provide yazi-actions)
(provide scooter-actions)

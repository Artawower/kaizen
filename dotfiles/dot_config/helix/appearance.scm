(require (prefix-in helix. "helix/commands.scm"))
(require "steel/result")
(require-builtin steel/core/result)
(require-builtin steel/process)
(require-builtin steel/strings)

(define (command-output name args)
  (~> (command name args)
    with-stdout-piped
    spawn-process
    (ok-and-then wait->stdout)
    (unwrap-or "")))

(define (system-appearance)
  (cond
    [(equal? (current-os!) "macos")
      (command-output "defaults" '("read" "-g" "AppleInterfaceStyle"))]
    [(equal? (current-os!) "linux")
      (command-output
        "gsettings"
        '("get" "org.gnome.desktop.interface" "color-scheme"))]
    [else ""]))

(define (dark-appearance? appearance)
  (define normalized (trim appearance))
  (or (equal? normalized "Dark")
    (equal? normalized "dark")
    (equal? normalized "prefer-dark")
    (equal? normalized "'prefer-dark'")))

(helix.theme
  (if (dark-appearance? (system-appearance)) "my" "my_light"))

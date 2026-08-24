(require "helix/configuration.scm")

(require "nrepl.hx/nrepl.scm")
(require "paredit.hx/paredit.scm")

(define-lsp "steel-language-server"
  (command "steel-language-server")
    (args '()))

    (define-language "scheme"
      (formatter
          (command "schemat"))
            (auto-format #true)
              (language-servers '("steel-language-server")))

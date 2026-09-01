(require (only-in "helix/editor.scm" editor-mode string->editor-mode))
(require (only-in "helix/static.scm" current-selection->string search search_selection search_next))

(provide search-smart)

(define *search-select-mode* (string->editor-mode "select"))

(define (search-smart)
  (let ([selection (current-selection->string)])
    (if (or (equal? (editor-mode) *search-select-mode*)
            (> (string-length selection) 1))
      (begin
        (search_selection)
        (search_next))
      (search))))

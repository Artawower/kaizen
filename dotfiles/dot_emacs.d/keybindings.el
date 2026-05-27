;;; keybindings.el — binding scheme dispatcher -*- lexical-binding: t; -*-
(require 'kaizen nil t)
(let ((scheme (or (bound-and-true-p kaizen/binding-scheme) "meow")))
  (load (expand-file-name (format "bindings/%s.el" scheme)
                          user-emacs-directory)
        nil t))
;;; keybindings.el ends here

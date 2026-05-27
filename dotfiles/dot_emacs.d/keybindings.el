;;; keybindings.el --- binding scheme dispatcher -*- lexical-binding: t; -*-
(require 'kaizen nil t)
(let* ((scheme (or (bound-and-true-p kaizen/binding-scheme) "meow"))
       (file (expand-file-name (format "bindings/%s.el" scheme)
                               user-emacs-directory)))
  (if (file-exists-p file)
      (load file nil t)
    (warn "kaizen/keybindings: binding scheme file not found: %s" file)))
;;; keybindings.el ends here

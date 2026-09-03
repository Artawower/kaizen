;;; keybindings.el --- binding scheme dispatcher -*- lexical-binding: t; -*-
(require 'kaizen nil t)

(defun kaizen/open-vcs-ui ()
  "Open the interface configured by `kaizen/preferred-vcs'."
  (interactive)
  (pcase (or (bound-and-true-p kaizen/preferred-vcs) "jj")
    ("jj" (call-interactively #'majutsu))
    ("git" (call-interactively #'magit-status))
    (vcs (user-error "Unsupported preferred VCS: %s" vcs))))

(let* ((scheme (or (bound-and-true-p kaizen/binding-scheme) "meow"))
       (file (expand-file-name (format "bindings/%s.el" scheme)
                               user-emacs-directory)))
  (if (file-exists-p file)
      (load file nil t)
    (warn "kaizen/keybindings: binding scheme file not found: %s" file)))
;;; keybindings.el ends here

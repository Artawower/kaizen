;;; init.el --- Emacs configuration entry point -*- lexical-binding: t; -*-

;;; Commentary:
;; This file loads the main configuration from README.org

;;; Code:
(setq custom-file (locate-user-emacs-file "custom.el"))

(let ((kaizen (expand-file-name "kaizen.el" user-emacs-directory)))
  (when (file-exists-p kaizen)
    (load kaizen nil t)))

(require 'org)
(require 'ob-python)
(add-to-list 'org-babel-load-languages '(python . t))
(org-babel-do-load-languages 'org-babel-load-languages org-babel-load-languages)
(condition-case err
    (org-babel-load-file "~/.emacs.d/README.org")
  (error (message "kaizen: README.org load error: %s" err)))

(when (file-exists-p custom-file)
  (load custom-file nil t))

(let ((local (expand-file-name "local.el" user-emacs-directory)))
  (when (file-exists-p local)
    (load local nil t)))

;;; init.el ends here

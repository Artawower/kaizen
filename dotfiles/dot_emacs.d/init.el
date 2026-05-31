;;; init.el --- Emacs configuration entry point -*- lexical-binding: t; -*-

;;; Commentary:
;; This file loads the main configuration from README.org

;;; Code:
(let ((kaizen (expand-file-name "kaizen.el" user-emacs-directory)))
  (when (file-exists-p kaizen)
    (load kaizen nil t)))

(require 'org)
(condition-case err
    (org-babel-load-file "~/.emacs.d/README.org")
  (error (message "kaizen: README.org load error: %s" err)))

(let ((local (expand-file-name "local.el" user-emacs-directory)))
  (when (file-exists-p local)
    (load local nil t)))

;;; init.el ends here

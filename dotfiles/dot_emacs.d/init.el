;;; init.el --- Emacs configuration entry point -*- lexical-binding: t; -*-

;;; Commentary:
;; This file loads the main configuration from README.org

;;; Code:
(let ((kaizen (expand-file-name "kaizen.el" user-emacs-directory)))
  (when (file-exists-p kaizen)
    (load kaizen nil t)))

(require 'org)
(org-babel-load-file "~/.emacs.d/README.org")

;;; init.el ends here

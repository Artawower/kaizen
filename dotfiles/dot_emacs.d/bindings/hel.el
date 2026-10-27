;;; bindings/hel.el --- Hel modal bindings -*- lexical-binding: t; -*-

(require 'kaizen nil t)

(defvar-keymap kaizen/hel-help-map
  "f" #'helpful-function
  "F" #'describe-face
  "v" #'helpful-variable
  "k" #'describe-key
  "t" #'load-theme)

(defvar-keymap kaizen/hel-vcs-map
  "l" #'kaizen/open-vcs-ui
  "h" #'git-timemachine)

(defvar-keymap kaizen/hel-bookmark-map
  "m" #'bm-toggle
  "l" #'bm-show)

(defvar-keymap kaizen/hel-org-link-map
  "s" #'org-store-link
  "l" #'org-insert-link
  "t" #'org-toggle-link-display
  "d" #'org-toggle-link-display)

(defvar-keymap kaizen/hel-window-map
  "f" #'zoom-window-zoom
  "q" #'delete-window
  "v" #'split-window-right
  "h" #'split-window-below
  "R" #'rotate-layout
  "r" #'rotate-window)

(defvar-keymap kaizen/hel-leader-map
  "b" kaizen/hel-bookmark-map
  "h" kaizen/hel-help-map
  "v" kaizen/hel-vcs-map
  "w" kaizen/hel-window-map
  "Q" #'save-buffers-kill-terminal
  "a c" #'my/copy-with-ai-context
  "b a" #'consult-buffer
  "b b" #'consult-project-buffer
  "f f" #'project-find-file
  "g r" #'git-gutter:revert-hunk
  "m l" kaizen/hel-org-link-map)

(set-keymap-parent kaizen/hel-leader-map mode-specific-map)

(defun kaizen/hel-avy-select-word ()
  "Jump to a word and select it."
  (interactive)
  (call-interactively #'avy-goto-word-1)
  (hel-mark-inner-word 1))

(defun kaizen/hel-insert-at-indentation ()
  "Move to indentation and enter Insert state."
  (interactive)
  (back-to-indentation)
  (hel-insert))

(defun kaizen/hel-recenter (&rest _)
  "Recenter after navigation."
  (recenter))

(defun kaizen/hel-search-or-next ()
  "Repeat search, or search for the selection or word at point."
  (interactive)
  (if (and (stringp (get-register '/))
           (not (equal (get-register '/) "")))
      (hel-search-next 1)
    (unless (use-region-p)
      (hel-mark-inner-word 1))
    (hel-construct-search-pattern)
    (hel-search-next 1)))

(defun kaizen/hel-enter-insert ()
  "Update UI integrations on entering Insert state."
  (when (fboundp 'my/disable-blamer-mode)
    (my/disable-blamer-mode))
  (when (boundp 'blamer--block-render-p)
    (setq blamer--block-render-p t))
  (when (fboundp 'blamer--clear-overlay)
    (blamer--clear-overlay))
  (when (fboundp 'my/toggle-flymake-posframe)
    (my/toggle-flymake-posframe)))

(defun kaizen/hel-enter-normal ()
  "Update UI integrations on entering Normal state."
  (when (fboundp 'corfu-quit)
    (ignore-errors (corfu-quit)))
  (when (fboundp 'blamer-mode)
    (blamer-mode 1))
  (when (boundp 'blamer--block-render-p)
    (setq blamer--block-render-p nil))
  (when (fboundp 'minuet-dismiss-suggestion)
    (minuet-dismiss-suggestion))
  (when (fboundp 'copilot-clear-overlay)
    (copilot-clear-overlay))
  (when (fboundp 'my/toggle-flymake-posframe)
    (my/toggle-flymake-posframe)))

(defun kaizen/hel-enable-normal-state ()
  "Activate Hel Normal state in the current buffer."
  (unless (bound-and-true-p hel-local-mode)
    (hel-local-mode 1))
  (unless (eq hel-state 'normal)
    (hel-switch-state 'normal)))

(defun kaizen/hel-initialize-startup-buffers ()
  "Start Hel in Normal state in the scratch and messages buffers."
  (dolist (name '("*scratch*" "*Messages*"))
    (when-let ((buffer (get-buffer name)))
      (with-current-buffer buffer
        (kaizen/hel-enable-normal-state)))))

(defun kaizen/hel-ediff-keybindings ()
  "Set Ediff control-buffer navigation keys."
  (when (keymapp (bound-and-true-p ediff-mode-map))
    (dolist (key '("j" "n" "SPC"))
      (keymap-set ediff-mode-map key #'ediff-next-difference))
    (dolist (key '("k" "e" "p" "S-SPC" "<backspace>" "<delete>"))
      (keymap-set ediff-mode-map key #'ediff-previous-difference))
    (keymap-set ediff-mode-map "?" #'ediff-toggle-help)
    (keymap-set ediff-mode-map "q" #'ediff-quit)
    (keymap-set ediff-mode-map "<escape>" #'ediff-quit)
    (hel-keymap-set ediff-mode-map :state 'emacs
      "SPC" #'ediff-next-difference)))

(use-package hel
  :ensure (:host github :repo "helheim-emacs/hel" :files (:defaults "**") :wait t)
  :demand t
  :custom
  (hel-normal-state-cursor-type 'box)
  (hel-insert-state-cursor-type 'bar)
  (hel-motion-state-cursor-type 'box)
  (hel-emacs-state-cursor-type 'hollow)
  (hel-want-minibuffer nil)
  :config
  (dolist (mode '(special-mode elpaca-info-mode
                               flymake-diagnostics-buffer-mode flycheck-error-list-mode
                               magit-mode magit-status-mode magit-log-mode magit-diff-mode
                               magit-process-mode compilation-mode debug-mode
                               debugger-mode grep-mode ediff-mode ediff-meta-mode))
    (hel-set-initial-state mode 'emacs))

  (dolist (mode '(prog-mode text-mode conf-mode fundamental-mode
                            lisp-interaction-mode emacs-lisp-mode ghostel-mode
                            messages-buffer-mode org-agenda-mode))
    (hel-set-initial-state mode 'normal))

  (dolist (mode '(dired-mode helpful-mode help-mode
                             majutsu-mode majutsu-log-mode majutsu-status-mode))
    (hel-set-initial-state mode 'motion))

  (hel-mode 1)
  ;; *Messages* can be initialized again after the initial startup.
  (add-hook 'messages-buffer-mode-hook #'kaizen/hel-enable-normal-state)
  (add-hook 'emacs-startup-hook #'kaizen/hel-initialize-startup-buffers)
  (when after-init-time
    (kaizen/hel-initialize-startup-buffers))

  (hel-keymap-global-set :state 'normal
    "SPC" kaizen/hel-leader-map
    "C-o" #'better-jumper-jump-backward
    "C-S-o" #'better-jumper-jump-forward
    "h" #'hel-backward-char
    "j" #'hel-next-line
    "k" #'hel-previous-line
    "l" #'hel-forward-char
    "0" #'hel-beginning-of-line-command
    "$" #'hel-end-of-line-command
    "I" #'kaizen/hel-insert-at-indentation
    "G" #'hel-end-of-buffer
    "r" #'hel-replace-with-kill-ring
    "R" #'hel-replace-char
    "c" #'hel-change
    "q" #'deactivate-mark
    "n" #'kaizen/hel-search-or-next
    "N" #'hel-search-previous
    "C-:" #'query-replace-regexp
    "C-j" #'flymake-goto-next-error
    "C-k" #'flymake-goto-prev-error
    "] d" #'flymake-goto-next-error
    "[ d" #'flymake-goto-prev-error
    "] m" #'bm-next
    "[ m" #'bm-previous
    "] g" #'git-gutter:next-hunk
    "[ g" #'git-gutter:previous-hunk
    "+" #'er/expand-region
    "f" #'kaizen/hel-avy-select-word
    "\\ f" #'avy-goto-char-timer
    "\\ p" #'apheleia-format-buffer
    "g s" #'smerge-next
    "g S" #'smerge-prev
    "z r" #'husky-fold-open
    "z R" #'husky-fold-open-all
    "z A" #'husky-fold-toggle-all
    "z a" #'husky-fold-toggle
    "z j" #'husky-fold-next
    "z M" #'husky-fold-close-all
    "z k" #'husky-fold-previous
    "#" #'persistent-kmacro-apply)

  (hel-keymap-global-set :state 'motion
    "SPC" kaizen/hel-leader-map)

  (hel-keymap-set global-map :state 'emacs
    "SPC" kaizen/hel-leader-map
    "C-o" #'better-jumper-jump-backward
    "C-S-o" #'better-jumper-jump-forward
    "] g" #'git-gutter:next-hunk
    "[ g" #'git-gutter:previous-hunk)

  (hel-keymap-global-set :state 'insert
    "TAB" #'indent-for-tab-command
    "C-w" my/delete-backward-word-binding
    "M-DEL" my/delete-backward-word-binding
    "M-<backspace>" my/delete-backward-word-binding)

  (keymap-global-set "s-c" #'hel-copy)
  (add-hook 'hel-insert-state-enter-hook #'kaizen/hel-enter-insert)
  (add-hook 'hel-normal-state-enter-hook #'kaizen/hel-enter-normal)

  (with-eval-after-load 'reviewer
    (keymap-set kaizen/hel-leader-map "r r" #'reviewer-transient))
  (with-eval-after-load 'undo-fu
    (hel-keymap-global-set :state 'normal
      "u" #'undo-fu-only-undo
      "U" #'undo-fu-only-redo))
  (with-eval-after-load 'dirvish
    (hel-keymap-global-set :state 'normal "g f" #'dirvish-quick-access))
  (with-eval-after-load 'eglot
    (hel-keymap-global-set :state 'normal
      "g i" #'eglot-find-implementation
      "g r" #'xref-find-references
      "\\ i" #'my/eglot-toggle-inlay-hints)
    (keymap-set kaizen/hel-leader-map "l a" #'eglot-code-actions)
    (keymap-set kaizen/hel-leader-map "l r" #'eglot-rename)
    (keymap-set kaizen/hel-leader-map "l h" #'eldoc)
    (keymap-set kaizen/hel-leader-map "l f" #'eglot-format-buffer)
    (keymap-set kaizen/hel-leader-map "l d" #'flymake-show-buffer-diagnostics))
  (with-eval-after-load 'lsp-proxy
    (keymap-set kaizen/hel-leader-map "l a" #'lsp-proxy-execute-code-action))
  (with-eval-after-load 'eldoc-box
    (hel-keymap-global-set :state 'normal
      "\\ b" #'my/toggle-eldoc-buffer
      "\\ h" #'eldoc-box-help-at-point))
  (with-eval-after-load 'pretty-ts-errors
    (hel-keymap-global-set :state 'normal
      "\\ e" #'pretty-ts-errors-show-error-at-point))
  (with-eval-after-load 'org
    (hel-keymap-global-set :state 'normal
      "\\ o" #'org-mode
      "\\ a" #'org-agenda))
  (with-eval-after-load 'google-translate
    (hel-keymap-global-set :state 'normal
      "\\ t" #'google-translate-smooth-translate))
  (with-eval-after-load 'husky
    (hel-keymap-global-set :state 'normal
      "g d" #'husky-lsp-find-definition
      "g D" #'husky-buffers-side-husky-actions-find-definition
      "%" #'husky-navigation-bounce-paren
      "g F" #'husky-lsp-avy-go-to-definition
      "g f" #'husky-lsp-avy-go-to-definition
      "s-y" #'husky-lsp-copy-to-register-1
      "s-p" #'husky-lsp-paste-from-register-1))
  (with-eval-after-load 'better-jumper
    (advice-add 'hel-forward-word-start :around
                #'my/better-jump-preserve-pos-advice))
  (with-eval-after-load 'git-gutter
    (advice-add 'git-gutter:next-hunk :after #'kaizen/hel-recenter)
    (advice-add 'git-gutter:previous-hunk :after #'kaizen/hel-recenter))
  (with-eval-after-load 'minuet
    (add-hook 'minuet-auto-suggestion-block-predicates
              (lambda () (not (eq hel-state 'insert))))
    (advice-add 'minuet-show-suggestion :around
                (lambda (orig &rest args)
                  (unless (eq hel-state 'normal)
                    (apply orig args)))))
  (with-eval-after-load 'copilot
    (advice-add 'copilot-show-overlay :override
                (lambda (completion uuid start end)
                  (unless (eq hel-state 'normal)
                    (copilot--display-overlay-completion
                     completion uuid start end)))))

  (with-eval-after-load 'dired
    (keymap-set dired-mode-map "SPC" kaizen/hel-leader-map)
    (keymap-set dired-mode-map "-" #'dired-up-directory)
    (keymap-set dired-mode-map "h" #'dired-up-directory)
    (keymap-set dired-mode-map "j" #'dired-next-line)
    (keymap-set dired-mode-map "k" #'dired-previous-line)
    (keymap-set dired-mode-map "l" #'dired-find-file))

  (with-eval-after-load 'majutsu-mode
    (hel-keymap-set majutsu-mode-map :state 'motion
      "j" #'next-line
      "k" #'previous-line
      "a" #'majutsu-abandon
      "A" #'majutsu-absorb))

  (with-eval-after-load 'helpful
    (keymap-set helpful-mode-map "SPC" kaizen/hel-leader-map))

  (with-eval-after-load 'help-mode
    (keymap-set help-mode-map "SPC" kaizen/hel-leader-map))

  (with-eval-after-load 'org-agenda
    (hel-keymap-set org-agenda-mode-map :state 'normal
      "<escape>" #'org-agenda-quit
      "SPC" kaizen/hel-leader-map
      "q" #'org-agenda-quit
      "g" #'org-agenda-redo
      "." #'org-agenda-goto-today
      "t" #'org-agenda-todo
      "s" #'org-agenda-schedule
      "d" #'org-agenda-deadline
      ":" #'org-agenda-set-tags
      "/" #'org-agenda-filter
      "v" #'org-agenda-view-mode-dispatch
      "TAB" #'org-agenda-goto
      "RET" #'org-agenda-switch-to
      "f" #'avy-goto-word-1
      "j" #'org-agenda-next-line
      "k" #'org-agenda-previous-line
      "h" #'org-agenda-earlier
      "l" #'org-agenda-later
      "J" #'org-agenda-next-item
      "K" #'org-agenda-previous-item))

  (with-eval-after-load 'ediff
    (kaizen/hel-ediff-keybindings)
    (add-hook 'ediff-keymap-setup-hook #'kaizen/hel-ediff-keybindings)
    (add-hook 'ediff-cleanup-hook
              (lambda ()
                (when (and hel-local-mode (not (minibufferp)))
                  (hel-switch-to-initial-state)))))

  (with-eval-after-load 'magit
    (keymap-set magit-mode-map ";" #'hel-collapse-selection)
    (keymap-set magit-status-mode-map "x" #'hel-expand-line-selection))

  (with-eval-after-load 'golden-ratio-scroll-screen
    (keymap-global-set "C-d" #'golden-ratio-scroll-screen-up)
    (keymap-global-set "C-u" #'golden-ratio-scroll-screen-down)))

(dolist (map (list minibuffer-local-map minibuffer-local-ns-map
                   minibuffer-local-completion-map
                   minibuffer-local-must-match-map read-expression-map))
  (keymap-set map "<escape>" #'abort-recursive-edit))

(provide 'kaizen-bindings-hel)
;;; bindings/hel.el ends here


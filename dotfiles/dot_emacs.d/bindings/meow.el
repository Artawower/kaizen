;;; bindings/meow.el — meow modal editing scheme -*- lexical-binding: t; -*-
(require 'kaizen nil t)

;;; Helper functions

(defun my/meow-yank-below ()
  "Yank below the current line."
  (interactive)
  (forward-line)
  (meow-yank))

(defun my/meow-change-till-eol ()
  "Change till the end of line."
  (interactive)
  (let ((meow-eol-thing 108))
    (meow-end-of-thing meow-eol-thing)
    (meow-change)))

(defun my/meow-select-till-eol ()
  "Select till the end of line."
  (interactive)
  (let ((meow-eol-thing 108))
    (meow-end-of-thing meow-eol-thing)))

(defun my/meow-backward-till (n ch)
  "Move backward till the first character that is not in the list of characters."
  (interactive "p\ncTill:")
  (meow-till -1 ch))

(defun my/meow--keypad-format-key-1 (key)
  "Return a display format for input KEY."
  (setq key `(,(car key) . ,(concat (mapcar (lambda (c) (reverse-im--translate-char c t)) (cdr key)))))
  (cl-case (car key)
    (meta (format "M-%s" (cdr key)))
    (control (format "C-%s" (meow--keypad-format-upcase (cdr key))))
    (both (format "C-M-%s" (meow--keypad-format-upcase (cdr key))))
    (literal (cdr key))))

;;; Core keybinding setup

(defun kaizen/meow-setup ()
  (setq meow--kbd-forward-line "<down>")
  (setq meow--kbd-backward-line "<up>")
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-colemak)
  (meow-motion-overwrite-define-key
   `(,(or (bound-and-true-p kaizen/nav-down) "n") . meow-next)
   `(,(or (bound-and-true-p kaizen/nav-up)   "e") . meow-prev)
   '("<escape>" . ignore))
  (meow-leader-define-key
   `(,(or (bound-and-true-p kaizen/nav-down) "n") . ,(format "H-%s" (or (bound-and-true-p kaizen/nav-down) "n")))
   `(,(or (bound-and-true-p kaizen/nav-up)   "e") . ,(format "H-%s" (or (bound-and-true-p kaizen/nav-up)   "e")))
   '("1" . meow-digit-argument)
   '("2" . meow-digit-argument)
   '("3" . meow-digit-argument)
   '("4" . meow-digit-argument)
   '("5" . meow-digit-argument)
   '("6" . meow-digit-argument)
   '("7" . meow-digit-argument)
   '("8" . meow-digit-argument)
   '("9" . meow-digit-argument)
   '("0" . meow-digit-argument)
   '("?" . meow-keypad-describe-key))
  (meow-normal-define-key
   '("*" . (lambda () (interactive)
             (call-interactively 'meow-mark-symbol)
             (call-interactively 'meow-search)))
   '("0" . meow-expand-0)
   '("9" . meow-expand-9)
   '("8" . meow-expand-8)
   '("7" . meow-expand-7)
   '("s-o" . meow-last-buffer)
   '("ge" . end-of-buffer)
   '("gg" . beginning-of-buffer)
   '("gl" . my/meow-select-till-eol)
   `("[b" . ,(my/bind meow-beginning-of-thing ?b))
   `("]b" . ,(my/bind meow-end-of-thing ?b))
   '("gi" . my/meow-select-till-eol)
   '("gh" . beginning-of-line)
   '("6" . meow-expand-6)
   '("@" . meow-end-or-call-kmacro)
   '("5" . meow-expand-5)
   '("4" . meow-expand-4)
   '("3" . meow-expand-3)
   '("2" . meow-expand-2)
   '("1" . meow-expand-1)
   '("-" . negative-argument)
   '("$" . my/meow-select-till-eol)
   '(";" . meow-reverse)
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("s-d" . meow-inner-of-thing)
   '("s-D" . meow-bounds-of-thing)
   '("M-[" . meow-beginning-of-thing)
   '("M-]" . meow-end-of-thing)
   `(,(or (bound-and-true-p kaizen/nav-insert) "l") . meow-append)
   '("o" . meow-open-below)
   '("b" . meow-back-word)
   '("B" . meow-back-symbol)
   '("c" . meow-change)
   '("d" . meow-delete)
   '("D" . meow-backward-delete)
   '("j" . meow-next-word)
   '("J" . meow-next-symbol)
   '("F" . meow-find)
   '("f" . avy-goto-word-1)
   '("q" . meow-cancel-selection)
   '("G" . meow-grab)
   `(,(or (bound-and-true-p kaizen/nav-left)  "h") . meow-left)
   `(,(upcase (or (bound-and-true-p kaizen/nav-left)  "h")) . meow-left-expand)
   '("a" . meow-insert)
   '("O" . meow-open-above)
   `(,(or (bound-and-true-p kaizen/nav-down)  "n") . meow-next)
   `(,(upcase (or (bound-and-true-p kaizen/nav-down)  "n")) . meow-next-expand)
   `(,(or (bound-and-true-p kaizen/nav-up)    "e") . meow-prev)
   `(,(upcase (or (bound-and-true-p kaizen/nav-up)    "e")) . meow-prev-expand)
   `(,(or (bound-and-true-p kaizen/nav-right) "i") . meow-right)
   `(,(upcase (or (bound-and-true-p kaizen/nav-right) "i")) . meow-right-expand)
   '("m" . meow-join)
   '("k" . meow-search)
   '("/" . meow-block)
   '("?" . meow-to-block)
   '("P" . meow-yank)
   '("C" . my/meow-change-till-eol)
   '("p" . my/meow-yank-below)
   '("r" . meow-replace)
   '("R" . meow-swap-grab)
   '("s" . meow-kill)
   '("t" . meow-till)
   '("{" . my/meow-backward-till)
   '("u" . meow-undo)
   '("U" . undo-fu-only-redo)
   '("v" . meow-visit)
   '("V" . meow-visual-line)
   '("w" . meow-mark-word)
   '("W" . meow-mark-symbol)
   '("x" . meow-line)
   '("X" . meow-goto-line)
   '("y" . meow-save)
   '("Y" . meow-sync-grab)
   '("Q" . meow-pop-selection)
   '("'" . repeat)
   '("=" . indent-for-tab-command)
   '(":" . query-replace-regexp)
   '("A" . my/edit-after-eol)
   '("L" . my/edit-before-bol)
   '("<escape>" . ignore))

  (meow-define-keys 'motion
   '("M-[" . meow-beginning-of-thing)
   '("M-]" . meow-end-of-thing)
   `("[b" . ,(my/bind meow-beginning-of-thing ?b))
   `("]b" . ,(my/bind meow-end-of-thing ?b))
   '("\\n" . meow-normal-mode)
   '("\\q" . kill-current-buffer))

  (meow-define-keys 'insert
    '("s-o" . meow-last-buffer)
    '("M-[" . meow-beginning-of-thing)
    '("M-]" . meow-end-of-thing)
    '("s-p" . xah-paste-from-register-1))

  (meow-define-keys 'normal
    '("\\q" . kill-current-buffer)
    '("T" . meow-till-expand)
    '("N" . my/copy-with-ai-context)
    '("z z" . recenter)
    '("C-<tab>" . indent-rigidly-right)
    '("<backtab>" . indent-rigidly-left)
    '("g c" . comment-or-uncomment-region)))

;;; Thing registration

(defun my/meow-thing-register ()
  (meow-thing-register 'whitespace '(regexp " \\|\n" " \\|\n") '(regexp " \\|\n" " \\|\n"))
  (add-to-list 'meow-char-thing-table '(?w . whitespace))

  (meow-thing-register 'non-whitespace
                         '(syntax . "-")
                         '(syntax . "-"))
  (add-to-list 'meow-char-thing-table '(?e . non-whitespace))

  (add-to-list 'meow-char-thing-table '(?\" . quoted))
  (add-to-list 'meow-char-thing-table '(?' . quoted))
  (add-to-list 'meow-char-thing-table '(?< . angle))

  (add-to-list 'meow-char-thing-table '(?\( . round))
  (add-to-list 'meow-char-thing-table '(?\) . round))

  (add-to-list 'meow-char-thing-table '(?{ . curly))
  (add-to-list 'meow-char-thing-table '(?} . curly))

  (add-to-list 'meow-char-thing-table '(?\[ . square))
  (add-to-list 'meow-char-thing-table '(?\] . square))

  (meow-thing-register 'quoted
                       '(regexp "\"\\|'\\|`" "\"\\|'\\|`")
                       '(regexp "\"\\|'\\|`" "\"\\|'\\|`"))

  (meow-thing-register 'angle
                       '(regexp "<" ">")
                       '(regexp "<" ">")))

;;; Agenda mode state

(defun my/meow-setup-agenda-mode ()
  (setq meow-agenda-motion-keymap (make-keymap))

  (meow-define-state agenda-motion
    "Org-Agenda motion"
    :lighter "[A]"
    :keymap meow-agenda-motion-keymap)

  (meow-define-keys 'agenda-motion
    '("<escape>" . org-agenda-quit)
    '("SPC" . meow-keypad)
    '("q" . org-agenda-quit)
    `(,(or (bound-and-true-p kaizen/nav-down)  "n") . org-agenda-next-line)
    `(,(or (bound-and-true-p kaizen/nav-up)    "e") . org-agenda-previous-line)
    `(,(or (bound-and-true-p kaizen/nav-left)  "h") . org-agenda-earlier)
    `(,(or (bound-and-true-p kaizen/nav-right) "i") . org-agenda-later)
    `(,(upcase (or (bound-and-true-p kaizen/nav-down)  "n")) . org-agenda-next-item)
    `(,(upcase (or (bound-and-true-p kaizen/nav-up)    "e")) . org-agenda-previous-item)
    '("f" . avy-goto-word-1)
    '("g" . org-agenda-redo)
    '("." . org-agenda-goto-today)
    '("t" . org-agenda-todo)
    '("s" . org-agenda-schedule)
    '("d" . org-agenda-deadline)
    '(":" . org-agenda-set-tags)
    '("j" . org-agenda-set-effort)
    '("/" . org-agenda-filter)
    '("\\" . org-agenda-filter-by-tag)
    '("v" . org-agenda-view-mode-dispatch)
    '("G" . org-agenda-toggle-time-grid)
    '("I" . org-agenda-log-mode)
    '("l" . org-agenda-clock-in)
    '("o" . org-agenda-clock-out)
    '("c" . org-agenda-capture)
    '("TAB" . org-agenda-goto)
    '("RET" . org-agenda-switch-to)
    '(" " . meow-keypad))

  (add-to-list 'meow-mode-state-list '(org-agenda-mode . agenda-motion)))

;;; Custom paren state

(defun my/meow-setup-custom-modes ()
  (setq meow-paren-keymap (make-keymap))
  (my/meow-setup-agenda-mode)
  (meow-define-state paren
    "meow state for interacting with smartparens"
    :lighter " [P]"
    :keymap meow-paren-keymap)

  (setq meow-cursor-type-paren 'hollow)

  (meow-define-keys 'paren
    '("<escape>" . meow-normal-mode)
    `(,(or (bound-and-true-p kaizen/nav-right) "i") . sp-forward-sexp)
    `(,(or (bound-and-true-p kaizen/nav-left)  "h") . sp-backward-sexp)
    `(,(or (bound-and-true-p kaizen/nav-down)  "n") . sp-down-sexp)
    `(,(or (bound-and-true-p kaizen/nav-up)    "e") . sp-up-sexp)
    '("k" . sp-forward-slurp-sexp)
    '("b" . sp-forward-barf-sexp)
    '("v" . sp-backward-barf-sexp)
    '("c" . sp-backward-slurp-sexp)
    '("u" . meow-undo))

  (meow-define-state disable
    "State for modes where Meow should stay out."
    :lighter " [x]"))

;;; Mode state list

(defun my/meow-setup-state-per-modes ()
  (add-to-list 'meow-mode-state-list '(elpaca-info-mode . normal))
  (add-to-list 'meow-mode-state-list '(flymake-diagnostics-buffer-mode . normal))
  (add-to-list 'meow-mode-state-list '(flycheck-error-list-mode . normal))
  (add-to-list 'meow-mode-state-list '(magit-process-mode . normal))
  (add-to-list 'meow-mode-state-list '(compilation-mode . normal))
  (add-to-list 'meow-mode-state-list '(helpful-mode . normal))
  (add-to-list 'meow-mode-state-list '(help-mode . normal))
  (add-to-list 'meow-mode-state-list '(detached-compilation-mode-map . normal))
  (add-to-list 'meow-mode-state-list '(messages-buffer-mode . normal))
  (add-to-list 'meow-mode-state-list '(debug-mode . normal))
  (add-to-list 'meow-mode-state-list '(debugger-mode . normal))
  (add-to-list 'meow-mode-state-list '(ediff-mode . ediff))
  (add-to-list 'meow-mode-state-list '(ediff-meta-mode . ediff))
  (add-to-list 'meow-mode-state-list '(grep-mode . normal)))

;;; Core packages

(use-package meow
  :custom
  (meow-use-clipboard t)
  :config
  (kaizen/meow-setup)
  (define-key mode-specific-map (kbd "j") nil)
  (define-key mode-specific-map (kbd "e") nil)
  (my/meow-thing-register)
  (my/meow-setup-custom-modes)
  (my/meow-setup-state-per-modes)
  (advice-add #'meow-change :after
              (lambda (&rest _)
                (when (and (bolp) (eolp))
                  (indent-according-to-mode))))
  (meow-global-mode 1))

(use-package meow-tree-sitter
  :ensure (:host github :repo "skissue/meow-tree-sitter")
  :after meow
  :config
  (meow-tree-sitter-register-defaults))

;;; Global binding

(with-eval-after-load 'meow
  (global-set-key (kbd "s-c") 'meow-save))

;;; Ediff state integration

(with-eval-after-load 'meow
  (defvar my/meow-ediff-state-keymap
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map meow-motion-state-keymap)
      (define-key map (kbd (or (bound-and-true-p kaizen/nav-down) "n")) #'ediff-next-difference)
      (define-key map (kbd (or (bound-and-true-p kaizen/nav-up)   "e")) #'ediff-previous-difference)
      map)
    "Meow keymap used while navigating Ediff buffers.")

  (defvar-local my/ediff-meow-was-enabled nil)
  (defvar-local my/ediff-meow-previous-state nil)

  (meow-define-state ediff
    "Meow state for Ediff navigation."
    :lighter " [M]"
    :keymap my/meow-ediff-state-keymap)

  (defun my/ediff-enable-meow-state ()
    "Ensure Meow is active and switch the current buffer into Ediff state."
    (when (bound-and-true-p meow-global-mode)
      (setq-local my/ediff-meow-was-enabled (bound-and-true-p meow-mode))
      (unless (bound-and-true-p meow-mode)
        (meow-mode 1))
      (unless (eq meow--current-state 'ediff)
        (setq-local my/ediff-meow-previous-state meow--current-state))
      (meow--switch-state 'ediff t)))

  (defun my/ediff-disable-meow-state ()
    "Restore the Meow setup used before Ediff."
    (let ((previous-state my/ediff-meow-previous-state)
          (was-enabled my/ediff-meow-was-enabled))
      (kill-local-variable 'my/ediff-meow-previous-state)
      (kill-local-variable 'my/ediff-meow-was-enabled)
      (cond
       ((and (bound-and-true-p meow-mode) previous-state)
        (meow--switch-state previous-state t))
       ((and (bound-and-true-p meow-mode) (not was-enabled))
        (meow-mode -1))))))

;;; reverse-im advice

(with-eval-after-load 'reverse-im
  (advice-add 'meow--keypad-format-key-1 :override #'my/meow--keypad-format-key-1))

;;; Package integrations

(with-eval-after-load 'zoom-window
  (define-key meow-normal-state-keymap (kbd "\\ m") #'zoom-window-zoom)
  (define-key meow-motion-state-keymap (kbd "\\ m") #'zoom-window-zoom))

(with-eval-after-load 'avy
  (define-key meow-normal-state-keymap (kbd "f") #'my/avy-select-word)
  (define-key meow-normal-state-keymap (kbd "\\f") #'avy-goto-char-timer))

(with-eval-after-load 'bm
  (define-key meow-normal-state-keymap (kbd "]m") #'bm-next)
  (define-key meow-normal-state-keymap (kbd "[m") #'bm-previous))

(with-eval-after-load 'undo-fu
  (define-key meow-normal-state-keymap (kbd "U") #'undo-fu-only-redo)
  (define-key meow-normal-state-keymap (kbd "u") #'undo-fu-only-undo))

(with-eval-after-load 'persistent-kmacro
  (define-key meow-normal-state-keymap (kbd "#") #'persistent-kmacro-apply))

(with-eval-after-load 'apheleia
  (define-key meow-normal-state-keymap (kbd "\\p") #'apheleia-format-buffer))

(with-eval-after-load 'dirvish
  (define-key meow-normal-state-keymap (kbd "gf") #'dirvish-quick-access))

(with-eval-after-load 'git-gutter
  (define-key meow-normal-state-keymap (kbd "]g") #'git-gutter:next-hunk)
  (define-key meow-normal-state-keymap (kbd "[g") #'git-gutter:previous-hunk))

(with-eval-after-load 'blamer
  (add-hook 'meow-insert-mode-hook #'my/disable-blamer-mode)
  (add-hook 'meow-normal-mode-hook #'blamer-mode))

(with-eval-after-load 'smerge-mode
  (define-key meow-normal-state-keymap (kbd "g s") #'smerge-next)
  (define-key meow-normal-state-keymap (kbd "g S") #'smerge-prev))

(with-eval-after-load 'ediff
  (remove-hook 'ediff-mode-hook #'meow-motion-mode)
  (remove-hook 'ediff-meta-mode-hook #'meow-motion-mode)
  (add-hook 'ediff-meta-mode-hook #'my/ediff-enable-meow-state)
  (add-hook 'ediff-startup-hook
            (lambda ()
              (when (buffer-live-p ediff-control-buffer)
                (with-current-buffer ediff-control-buffer
                  (my/ediff-enable-meow-state)))))
  (add-hook 'ediff-cleanup-hook #'my/ediff-disable-meow-state))

(with-eval-after-load 'eglot
  (define-key meow-normal-state-keymap (kbd "g i") #'eglot-find-implementation)
  (define-key meow-normal-state-keymap (kbd "g r") #'xref-find-references)
  (define-key meow-normal-state-keymap (kbd "\\i") #'my/eglot-toggle-inlay-hints)
  (define-key meow-normal-state-keymap (kbd "\\l") #'eglot-code-actions))

(with-eval-after-load 'corfu
  (add-hook 'meow-insert-exit-hook (lambda () (corfu-quit))))

(with-eval-after-load 'flymake
  (define-key meow-normal-state-keymap (kbd "]d") #'flymake-goto-next-error)
  (define-key meow-normal-state-keymap (kbd "[d") #'flymake-goto-prev-error)
  (add-hook 'flymake-diagnostics-buffer-mode-hook #'meow-normal-mode))

(with-eval-after-load 'flymake-posframe
  (add-hook 'meow-normal-mode-hook #'my/toggle-flymake-posframe)
  (add-hook 'meow-insert-mode-hook #'my/toggle-flymake-posframe))

(with-eval-after-load 'eldoc-box
  (define-key meow-normal-state-keymap (kbd "\\b") #'my/toggle-eldoc-buffer)
  (define-key meow-normal-state-keymap (kbd "\\h") #'eldoc-box-help-at-point))

(with-eval-after-load 'pretty-ts-errors
  (define-key meow-normal-state-keymap (kbd "\\e") #'pretty-ts-errors-show-error-at-point))

(with-eval-after-load 'org
  (define-key meow-normal-state-keymap (kbd "\\o") #'org-mode)
  (define-key meow-normal-state-keymap (kbd "\\a") #'org-agenda))

(with-eval-after-load 'google-translate
  (define-key meow-normal-state-keymap (kbd "\\ t") #'google-translate-smooth-translate))

(with-eval-after-load 'copilot
  (add-hook 'meow-insert-enter-hook (lambda ()
                                      (setq blamer--block-render-p t)
                                      (blamer--clear-overlay)))
  (add-hook 'meow-insert-exit-hook (lambda ()
                                     (setq blamer--block-render-p nil)
                                     (copilot-clear-overlay)))

  (defun my/copilot-show-overlay-depends-mode (COMPLETION UUID START END)
    (unless (bound-and-true-p meow-normal-mode)
      (copilot--display-overlay-completion COMPLETION UUID START END)))
  (advice-add 'copilot-show-overlay :override #'my/copilot-show-overlay-depends-mode))

(with-eval-after-load 'husky
  (define-key meow-normal-state-keymap (kbd "gd") #'husky-lsp-find-definition)
  (define-key meow-normal-state-keymap (kbd "%") #'husky-navigation-bounce-paren)
  (define-key meow-normal-state-keymap (kbd "g F") #'husky-lsp-avy-go-to-definition)
  (define-key meow-normal-state-keymap (kbd "g f") #'husky-lsp-avy-go-to-definition)
  (define-key meow-normal-state-keymap (kbd "g D") #'husky-buffers-side-husky-actions-find-definition)
  (define-key meow-normal-state-keymap (kbd "z r") #'husky-fold-open)
  (define-key meow-normal-state-keymap (kbd "z R") #'husky-fold-open-all)
  (define-key meow-normal-state-keymap (kbd "s-y") #'husky-lsp-copy-to-register-1)
  (define-key meow-normal-state-keymap (kbd "s-p") #'husky-lsp-paste-from-register-1)
  (define-key meow-normal-state-keymap (kbd "z A") #'husky-fold-toggle-all)
  (define-key meow-normal-state-keymap (kbd "z a") #'husky-fold-toggle)
  (define-key meow-normal-state-keymap (kbd "z j") #'husky-fold-next)
  (define-key meow-normal-state-keymap (kbd "z M") #'husky-fold-close-all)
  (define-key meow-normal-state-keymap (kbd "z k") #'husky-fold-previous))

(with-eval-after-load 'magit
  (define-key magit-mode-map        (kbd ";") #'meow-reverse)
  (define-key magit-status-mode-map (kbd "x") #'meow-line))

(with-eval-after-load 'better-jumper
  (advice-add 'meow-end-of-thing :around #'my/better-jump-preserve-pos-advice))

;;; bindings/meow.el ends here

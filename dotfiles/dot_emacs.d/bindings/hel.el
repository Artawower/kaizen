;;; bindings/hel.el --- hel (Helix-style) modal editing scheme -*- lexical-binding: t; -*-
(when (featurep 'kaizen-bindings-hel)
  (user-error "kaizen-bindings-hel already loaded"))

(require 'kaizen nil t)

(use-package hel
  :ensure (:host github :repo "anuvyklack/hel" :files (:defaults "**") :wait t)
  :demand t
  :custom
  (hel-normal-state-cursor-type 'box)
  (hel-insert-state-cursor-type 'bar)
  (hel-motion-state-cursor-type 'hollow)
  :config
  ;; Disable hel in minibuffer — hard disable via hook (higher priority than hel's own)
  (setopt hel-want-minibuffer nil)
  (remove-hook 'minibuffer-setup-hook 'hel-local-mode)
  (defun kaizen/hel-disable-in-minibuffer ()
    (when (bound-and-true-p hel-local-mode)
      (hel-local-mode -1)))
  (add-hook 'minibuffer-setup-hook #'kaizen/hel-disable-in-minibuffer 100)
  ;; Explicit <escape> in all minibuffer maps — ensures abort works
  
  (hel-keymap-global-set :state '(normal motion)
    "C-o" #'better-jumper-jump-backward
    "C-S-o" #'better-jumper-jump-forward)
  (hel-keymap-global-set :state 'insert
    "TAB" #'self-insert-command))

(dolist (map (list minibuffer-local-map
                   minibuffer-local-ns-map
                   minibuffer-local-completion-map
                   minibuffer-local-must-match-map
                   read-expression-map))
  (keymap-set map "<escape>" #'abort-recursive-edit))

(defun kaizen/hel-G (arg)
  "Go to line ARG, or end of buffer if no ARG."
  (interactive "P")
  (if arg (goto-line (prefix-numeric-value arg)) (hel-end-of-buffer)))

(defun kaizen/hel-insert-at-indentation ()
  "Move to the first non-blank character, then switch to Insert state."
  (interactive)
  (back-to-indentation)
  (hel-insert-state 1))

(hel-define-command kaizen/hel-change ()
  "Delete region without touching `kill-ring', then switch to Insert state."
  :multiple-cursors nil
  (interactive "*")
  (hel-with-each-cursor
    (cond ((use-region-p)
           (let ((logical-lines? (hel-linewise-selection-p))
                 (visual-lines? (hel-visual-lines-p)))
             (delete-region (region-beginning) (region-end))
             (cond (logical-lines?
                    (newline)
                    (backward-char)
                    (indent-according-to-mode))
                   (visual-lines?
                    (insert " ")
                    (backward-char)))))
          ((not (hel-bolp))
           (delete-char -1))
          ((bolp)
           (indent-according-to-mode))))
  (hel-insert-state 1))

(defvar-keymap kaizen/hel-help-map
  "f" #'helpful-function
  "F" #'describe-face
  "v" #'helpful-variable
  "k" #'describe-key
  "t" #'load-theme)

(defun kaizen/hel-avy-select-word ()
  "Jump to word with avy, then select it (hel-aware)."
  (interactive)
  (call-interactively #'avy-goto-word-1)
  (hel-mark-inner-word 1))

(defun kaizen/hel-search-or-next ()
  "If searching, go to next match. Otherwise search for selection or word under cursor."
  (interactive)
  (if (ignore-errors (hel-search-pattern))
      (hel-search-next 1)
    (unless (region-active-p)
      (hel-mark-inner-word 1))
    (when (region-active-p)
      (hel-construct-search-pattern)
      (deactivate-mark)
      (hel-search-next 1))))

(defun kaizen/hel-search-with-region ()
  "Start search. If region is active, pre-fill with selection."
  (interactive)
  (when (region-active-p)
    (let ((sel (buffer-substring-no-properties (region-beginning) (region-end))))
      (deactivate-mark)
      (when (and sel (not (string-empty-p sel)))
        (set-register '/ sel))))
  (hel-search-interactively))

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
  "r" #'rotate-window)

(let* ((left  (or (bound-and-true-p kaizen/nav-left)   "h"))
       (down  (or (bound-and-true-p kaizen/nav-down)   "n"))
       (up    (or (bound-and-true-p kaizen/nav-up)     "e"))
       (right (or (bound-and-true-p kaizen/nav-right)  "i"))
       (ins   (or (bound-and-true-p kaizen/nav-insert) "l"))
       (line-start (or (bound-and-true-p kaizen/line-start) "0"))
       (line-end   (or (bound-and-true-p kaizen/line-end)   "$")))

  (hel-keymap-global-set :state 'normal
    left  #'hel-backward-char
    down  #'hel-next-line
    up    #'hel-previous-line
    right #'hel-forward-char
    ins   #'hel-append
    (upcase ins) #'kaizen/hel-insert-at-indentation
    "k"   #'kaizen/hel-search-or-next
    "r"   #'hel-replace-with-kill-ring
    "j"   #'hel-forward-word-start
    "J"   #'hel-forward-WORD-start
    "c"   #'kaizen/hel-change
    "q"   #'deactivate-mark
    line-start #'beginning-of-line
    line-end   #'end-of-line
    "G"   #'kaizen/hel-G
    "N"   #'my/copy-with-ai-context
    "C-:" #'query-replace-regexp
    "/"   #'kaizen/hel-search-with-region
    "SPC" mode-specific-map)

  (keymap-set hel-normal-state-map "C-n" #'flymake-goto-next-error)
  (keymap-set hel-normal-state-map "C-e" #'flymake-goto-prev-error)
  (keymap-set hel-normal-state-map "] d" #'flymake-goto-next-error)
  (keymap-set hel-normal-state-map "[ d" #'flymake-goto-prev-error)

  (keymap-set mode-specific-map "b" kaizen/hel-bookmark-map)
  (keymap-set mode-specific-map "h" kaizen/hel-help-map)
  (keymap-set mode-specific-map "v" kaizen/hel-vcs-map)
  (keymap-set mode-specific-map "w" kaizen/hel-window-map)

  (hel-keymap-global-set :state 'motion
    left  #'hel-backward-char
    down  #'hel-next-line
    up    #'hel-previous-line
    right #'hel-forward-char
    (upcase ins) #'back-to-indentation
    line-start #'beginning-of-line
    line-end   #'end-of-line
    "SPC" mode-specific-map)

  (global-set-key (kbd "s-c") #'hel-copy)

  (dolist (mode '(prog-mode text-mode conf-mode fundamental-mode))
    (hel-set-initial-state mode 'normal))

  (dolist (mode '(elpaca-info-mode flymake-diagnostics-buffer-mode
                                   flycheck-error-list-mode magit-process-mode
                                   compilation-mode helpful-mode help-mode
                                   debug-mode debugger-mode
                                   grep-mode))
    (hel-set-initial-state mode 'motion))

  (hel-define-state ediff "Hel state for Ediff." :cursor '(hbar . 4))
  (hel-set-initial-state 'ediff-mode      'ediff)
  (hel-set-initial-state 'ediff-meta-mode 'ediff)
  (hel-keymap-set hel-ediff-state-map
    "<escape>" #'hel-normal-state
    down       #'ediff-next-difference
    up         #'ediff-previous-difference)

  (hel-set-initial-state 'org-agenda-mode 'normal)

  (with-eval-after-load 'org-agenda
    (hel-keymap-set org-agenda-mode-map :state 'normal
      "<escape>" #'org-agenda-quit
      "SPC"      mode-specific-map
      "q"        #'org-agenda-quit
      "g"        #'org-agenda-redo
      "."        #'org-agenda-goto-today
      "t"        #'org-agenda-todo
      "s"        #'org-agenda-schedule
      "d"        #'org-agenda-deadline
      ":"        #'org-agenda-set-tags
      "/"        #'org-agenda-filter
      "v"        #'org-agenda-view-mode-dispatch
      "TAB"      #'org-agenda-goto
      "RET"      #'org-agenda-switch-to
      "f"        #'avy-goto-word-1
      down       #'org-agenda-next-line
      up         #'org-agenda-previous-line
      left       #'org-agenda-earlier
      right      #'org-agenda-later
      (upcase down) #'org-agenda-next-item
      (upcase up)   #'org-agenda-previous-item))

  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-agenda-mode)
        (hel-normal-state 1)))))

;; Package integrations — with-eval-after-load inside :config
;; hel is guaranteed loaded here, packages may load later
(with-eval-after-load 'avy
  (hel-keymap-global-set :state 'normal
    "f"   #'kaizen/hel-avy-select-word
    "\\ f" #'avy-goto-char-timer))

(with-eval-after-load 'bm
  (hel-keymap-global-set :state 'normal
    "] m"   #'bm-next
    "[ m"   #'bm-previous
    "SPC b m" #'bm-toggle
    "SPC b l" #'bm-show))

(with-eval-after-load 'undo-fu
  (hel-keymap-global-set :state 'normal
    "u" #'undo-fu-only-undo
    "U" #'undo-fu-only-redo))

(with-eval-after-load 'persistent-kmacro
  (hel-keymap-global-set :state 'normal "#" #'persistent-kmacro-apply))

(with-eval-after-load 'apheleia
  (hel-keymap-global-set :state 'normal "\\ p" #'apheleia-format-buffer))

(with-eval-after-load 'consult
  (hel-keymap-global-set :state 'normal "SPC b a" #'consult-buffer)
  (hel-keymap-global-set :state 'normal "SPC b b" #'consult-project-buffer))

(hel-keymap-global-set :state 'normal
  "SPC f f" #'project-find-file)

(with-eval-after-load 'dirvish
  (hel-keymap-global-set :state 'normal "g f" #'dirvish-quick-access))

(hel-keymap-global-set :state '(normal motion)
  "SPC g r" #'git-gutter:revert-hunk
  "] g" #'git-gutter:next-hunk
  "[ g" #'git-gutter:previous-hunk)

(with-eval-after-load 'git-timemachine
  (hel-keymap-global-set :state 'normal
    (concat "SPC " (or (bound-and-true-p kaizen/vcs-history) "v h")) #'git-timemachine))

(with-eval-after-load 'blamer
  (add-hook 'hel-insert-state-enter-hook #'my/disable-blamer-mode)
  (add-hook 'hel-normal-state-enter-hook #'blamer-mode))

(with-eval-after-load 'smerge-mode
  (hel-keymap-global-set :state 'normal
    "g s" #'smerge-next
    "g S" #'smerge-prev))

(with-eval-after-load 'ediff
  (add-hook 'ediff-startup-hook
            (lambda ()
              (when (buffer-live-p ediff-control-buffer)
                (with-current-buffer ediff-control-buffer
                  (hel-ediff-state 1)))))
  (add-hook 'ediff-cleanup-hook
            (lambda ()
              (when (bound-and-true-p hel-local-mode)
                (hel-normal-state 1)))))

(with-eval-after-load 'eglot
  (hel-keymap-global-set :state 'normal
    "g i"       #'eglot-find-implementation
    "g r"       #'xref-find-references
    "\\ i"     #'my/eglot-toggle-inlay-hints
    "SPC l a"   #'eglot-code-actions
    "SPC l r"   #'eglot-rename
    "SPC l h"   #'eldoc
    "SPC l f"   #'eglot-format-buffer
    "SPC l d"   #'flymake-show-buffer-diagnostics))

(with-eval-after-load 'corfu
  (add-hook 'hel-insert-state-exit-hook (lambda () (corfu-quit))))

;; Toggle hel in minibuffer on demand (C-z since hel is off there by default)
(define-key minibuffer-local-map          (kbd "C-z") #'hel-local-mode)
(define-key minibuffer-local-completion-map (kbd "C-z") #'hel-local-mode)
(define-key minibuffer-local-ns-map       (kbd "C-z") #'hel-local-mode)



(with-eval-after-load 'flymake-posframe
  (add-hook 'hel-normal-state-enter-hook #'my/toggle-flymake-posframe)
  (add-hook 'hel-insert-state-enter-hook #'my/toggle-flymake-posframe))

(with-eval-after-load 'eldoc-box
  (hel-keymap-global-set :state 'normal
    "\\ b" #'my/toggle-eldoc-buffer
    "\\ h" #'eldoc-box-help-at-point))

(with-eval-after-load 'pretty-ts-errors
  (hel-keymap-global-set :state 'normal
    "\\ e" #'pretty-ts-errors-show-error-at-point))

(with-eval-after-load 'org
  (keymap-set mode-specific-map "m l" kaizen/hel-org-link-map)
  (hel-keymap-global-set :state 'normal
    "\\ o" #'org-mode
    "\\ a" #'org-agenda
    "SPC m l l" #'org-insert-link
    "SPC m l t" #'org-toggle-link-display
    "SPC m l d" #'org-toggle-link-display
    "SPC m l s" #'org-store-link))

(with-eval-after-load 'google-translate
  (hel-keymap-global-set :state 'normal
    "\\ t" #'google-translate-smooth-translate))

(with-eval-after-load 'magit
  (keymap-set magit-mode-map        ";" #'hel-collapse-selection)
  (keymap-set magit-status-mode-map "x" #'hel-expand-line-selection))

(with-eval-after-load 'copilot
  (add-hook 'hel-insert-state-enter-hook
            (lambda () (setq blamer--block-render-p t) (blamer--clear-overlay)))
  (add-hook 'hel-insert-state-exit-hook
            (lambda () (setq blamer--block-render-p nil) (copilot-clear-overlay)))
  (advice-add 'copilot-show-overlay :override
              (lambda (completion uuid start end)
                (unless (bound-and-true-p hel-normal-state)
                  (copilot--display-overlay-completion completion uuid start end)))))

;; husky LSP — deferred until husky loads
(with-eval-after-load 'husky
  (hel-keymap-global-set :state 'normal
    "g d" #'husky-lsp-find-definition
    "g D" #'husky-buffers-side-husky-actions-find-definition
    "%"   #'husky-navigation-bounce-paren
    "g F" #'husky-lsp-avy-go-to-definition
    "g f" #'husky-lsp-avy-go-to-definition
    "g D" #'husky-buffers-side-husky-actions-find-definition
    "s-y" #'husky-lsp-copy-to-register-1
    "s-p" #'husky-lsp-paste-from-register-1))



(with-eval-after-load 'better-jumper
  (advice-add 'hel-forward-word-start :around
              #'my/better-jump-preserve-pos-advice))

;; husky-fold — public API via husky-autoloads
(let ((fold-next (concat "z " (or (bound-and-true-p kaizen/nav-down) "j")))
      (fold-prev (concat "z " (or (bound-and-true-p kaizen/nav-up) "k"))))
  (hel-keymap-global-set :state 'normal
    "z r" #'husky-fold-open
    "z R" #'husky-fold-open-all
    "z A" #'husky-fold-toggle-all
    "z a" #'husky-fold-toggle
    fold-next #'husky-fold-next
    "z M"     #'husky-fold-close-all
    fold-prev #'husky-fold-previous)

;; Activate after all state/keymap configuration is complete
(hel-mode)



(provide 'kaizen-bindings-hel)
;;; bindings/hel.el ends here

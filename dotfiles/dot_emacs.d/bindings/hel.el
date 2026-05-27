;;; bindings/hel.el --- hel (Helix-style) modal editing scheme -*- lexical-binding: t; -*-
(when (featurep 'kaizen-bindings-hel)
  (user-error "kaizen-bindings-hel already loaded"))

(require 'kaizen nil t)

;;; Dependencies

(use-package dash   :ensure t)
(use-package pcre2el :ensure t)

;;; Core package

(use-package hel
  :ensure (:host github :repo "anuvyklack/hel" :files (:defaults "**"))
  :config
  (hel-mode))

;;; Nav key remapping — Colemak HNEI layout via kaizen/nav-* vars
;;
;; hel default uses hjkl (QWERTY).  We remap to the layout-aware kaizen keys.
;;
;; Colemak displacement table:
;;   kaizen key → command      was previously
;;   n (nav-down)   → hel-next-line       ← displaced hel-search-next
;;   e (nav-up)     → hel-previous-line   ← displaced hel-forward-word-end
;;   i (nav-right)  → hel-forward-char    ← displaced hel-insert
;;   l (nav-insert) → hel-append          ← displaced hel-forward-char
;;   k (now free)   → hel-search-forward  ← was nav-up, repurposed for search
;;   j (now free)   → hel-forward-word-start (was nav-down in QWERTY)

(with-eval-after-load 'hel
  (let* ((left  (or (bound-and-true-p kaizen/nav-left)   "h"))
         (down  (or (bound-and-true-p kaizen/nav-down)   "n"))
         (up    (or (bound-and-true-p kaizen/nav-up)     "e"))
         (right (or (bound-and-true-p kaizen/nav-right)  "i"))
         (ins   (or (bound-and-true-p kaizen/nav-insert) "l")))

    ;; Normal state — nav keys
    (keymap-set hel-normal-state-map left  #'hel-backward-char)
    (keymap-set hel-normal-state-map down  #'hel-next-line)
    (keymap-set hel-normal-state-map up    #'hel-previous-line)
    (keymap-set hel-normal-state-map right #'hel-forward-char)
    ;; Insert mode entry on nav-insert key (colemak: l)
    (keymap-set hel-normal-state-map ins   #'hel-append)

    ;; Uppercase nav → selection-extending variants
    (keymap-set hel-normal-state-map (upcase left)  #'hel-backward-char)
    (keymap-set hel-normal-state-map (upcase down)  #'hel-next-line)
    (keymap-set hel-normal-state-map (upcase up)    #'hel-previous-line)
    (keymap-set hel-normal-state-map (upcase right) #'hel-forward-char)

    ;; Motion state — nav keys
    (keymap-set hel-motion-state-map left  #'hel-backward-char)
    (keymap-set hel-motion-state-map down  #'hel-next-line)
    (keymap-set hel-motion-state-map up    #'hel-previous-line)
    (keymap-set hel-motion-state-map right #'hel-forward-char)

    ;; Displaced key repurposing:
    ;;   k is no longer nav-up → repurpose for search (meow had 'k' = search)
    (keymap-set hel-normal-state-map "k" #'hel-search-forward)
    ;;   j is no longer nav-down → repurpose for word-forward (meow had 'j')
    (keymap-set hel-normal-state-map "j" #'hel-forward-word-start)
    (keymap-set hel-normal-state-map "J" #'hel-forward-WORD-start)))

;;; Additional meow-compatible command mappings

(with-eval-after-load 'hel
  ;; gg/G — buffer start/end (built-in hel: gg = hel-beginning-of-buffer, G = hel-end-of-buffer)
  ;; gh/gl — bol/eol (built-in hel: g h = hel-beginning-of-line-command, g l = hel-end-of-line-command)
  ;; [b/]b — prev/next buffer (built-in hel)
  ;; o/O — open line below/above (built-in hel: hel-open-below / hel-open-above)
  ;; f/F, t/T — find/till char (built-in hel)
  ;; d/c — cut/change (built-in hel: hel-cut / hel-change)
  ;; y/p/P — copy/paste (built-in hel: hel-copy / hel-paste-after / hel-paste-before)
  ;; * — search symbol (built-in hel: hel-construct-search-pattern)
  ;; w/W — word motion (built-in hel: hel-forward-word-start / hel-forward-WORD-start)
  ;; u/U — undo/redo (built-in hel: hel-undo / hel-redo)
  ;; x/X — linewise selection (built-in hel: hel-expand-line-selection / backward)
  ;; v — extend selection (built-in hel: hel-extend-selection)

  ;; Meow-specific mappings without direct hel equivalent → closest analog
  (hel-keymap-global-set :state 'normal
    ;; ; = collapse selection (meow-reverse ≈ hel-collapse-selection, built-in as ;)
    ;; . = repeat last command (built-in hel)
    ;; m = join line (meow-join ≈ hel-join-line J, but also bind m)
    "m" #'hel-join-line
    ;; : = query-replace-regexp (meow had ':', hel uses ':' for execute-extended-command)
    ;; Rebind to M-: to avoid conflict; map C-: to query-replace-regexp
    "C-:" #'query-replace-regexp
    ;; = indent (built-in hel as '=')
    ;; q = deactivate mark (meow-cancel-selection)
    "q" #'deactivate-mark
    ;; A = insert at end of line
    "A" #'hel-append-line
    ;; L = insert at beginning of line (meow had 'L' = my/edit-before-bol)
    "L" #'hel-insert-line
    ;; D = delete to EOL
    "D" #'hel-delete
    ;; C = change to EOL
    "C" #'hel-change))

;;; Global binding

(with-eval-after-load 'hel
  (global-set-key (kbd "s-c") #'hel-copy))

;;; State configuration for special modes

(with-eval-after-load 'hel
  (hel-set-initial-state 'elpaca-info-mode           'motion)
  (hel-set-initial-state 'flymake-diagnostics-buffer-mode 'motion)
  (hel-set-initial-state 'flycheck-error-list-mode   'motion)
  (hel-set-initial-state 'magit-process-mode         'motion)
  (hel-set-initial-state 'compilation-mode           'motion)
  (hel-set-initial-state 'helpful-mode               'motion)
  (hel-set-initial-state 'help-mode                  'motion)
  (hel-set-initial-state 'messages-buffer-mode       'motion)
  (hel-set-initial-state 'debug-mode                 'motion)
  (hel-set-initial-state 'debugger-mode              'motion)
  (hel-set-initial-state 'grep-mode                  'motion))

;;; Custom states

(with-eval-after-load 'hel
  ;; Ediff navigation state
  (hel-define-state ediff
    "Hel state for Ediff buffer navigation."
    :cursor '(hbar . 4)
    :modes '(ediff-mode ediff-meta-mode))

  (let ((down (or (bound-and-true-p kaizen/nav-down) "n"))
        (up   (or (bound-and-true-p kaizen/nav-up)   "e")))
    (keymap-set hel-ediff-state-map down #'ediff-next-difference)
    (keymap-set hel-ediff-state-map up   #'ediff-previous-difference)
    (keymap-set hel-ediff-state-map "<escape>" #'hel-normal-state))

  ;; Org-agenda motion state
  (hel-define-state agenda-motion
    "Hel state for Org-Agenda navigation."
    :modes '(org-agenda-mode))

  (let ((down  (or (bound-and-true-p kaizen/nav-down)  "n"))
        (up    (or (bound-and-true-p kaizen/nav-up)    "e"))
        (left  (or (bound-and-true-p kaizen/nav-left)  "h"))
        (right (or (bound-and-true-p kaizen/nav-right) "i")))
    (hel-keymap-set hel-agenda-motion-state-map
      "<escape>" #'org-agenda-quit
      "SPC"      #'execute-extended-command
      "q"        #'org-agenda-quit
      "g"        #'org-agenda-redo
      "."        #'org-agenda-goto-today
      "t"        #'org-agenda-todo
      "s"        #'org-agenda-schedule
      "d"        #'org-agenda-deadline
      ":"        #'org-agenda-set-tags
      "j"        #'org-agenda-set-effort
      "/"        #'org-agenda-filter
      "\\"       #'org-agenda-filter-by-tag
      "v"        #'org-agenda-view-mode-dispatch
      "G"        #'org-agenda-toggle-time-grid
      "I"        #'org-agenda-log-mode
      "l"        #'org-agenda-clock-in
      "o"        #'org-agenda-clock-out
      "c"        #'org-agenda-capture
      "TAB"      #'org-agenda-goto
      "RET"      #'org-agenda-switch-to
      "f"        #'avy-goto-word-1)
    (keymap-set hel-agenda-motion-state-map down  #'org-agenda-next-line)
    (keymap-set hel-agenda-motion-state-map up    #'org-agenda-previous-line)
    (keymap-set hel-agenda-motion-state-map left  #'org-agenda-earlier)
    (keymap-set hel-agenda-motion-state-map right #'org-agenda-later)
    (keymap-set hel-agenda-motion-state-map (upcase down) #'org-agenda-next-item)
    (keymap-set hel-agenda-motion-state-map (upcase up)   #'org-agenda-previous-item)))

;;; NOT PORTED:
;;   meow-keypad          — no equivalent in hel (hel uses ':' for M-x)
;;   meow-tree-sitter     — no equivalent
;;   meow-visit           — replaced by hel built-in 'g d' (xref-find-definitions)
;;   meow-sync-grab / meow-pop-selection — no equivalent
;;   my/meow--keypad-format-key-1 — not needed (no keypad in hel)
;;   reverse-im advice   — not needed (hel doesn't use keypad)
;;   my/meow-thing-register — hel uses its own 'm*' text object commands

;;; Package integrations

(with-eval-after-load 'zoom-window
  (keymap-set hel-normal-state-map "\\ m" #'zoom-window-zoom)
  (keymap-set hel-motion-state-map "\\ m" #'zoom-window-zoom))

(with-eval-after-load 'avy
  (keymap-set hel-normal-state-map "f"  #'my/avy-select-word)
  (keymap-set hel-normal-state-map "\\f" #'avy-goto-char-timer))

(with-eval-after-load 'bm
  (keymap-set hel-normal-state-map "]m" #'bm-next)
  (keymap-set hel-normal-state-map "[m" #'bm-previous))

(with-eval-after-load 'undo-fu
  ;; Replace hel's built-in undo/redo with undo-fu for consistent history
  (keymap-set hel-normal-state-map "u" #'undo-fu-only-undo)
  (keymap-set hel-normal-state-map "U" #'undo-fu-only-redo))

(with-eval-after-load 'persistent-kmacro
  (keymap-set hel-normal-state-map "#" #'persistent-kmacro-apply))

(with-eval-after-load 'apheleia
  (keymap-set hel-normal-state-map "\\p" #'apheleia-format-buffer))

(with-eval-after-load 'dirvish
  (keymap-set hel-normal-state-map "gf" #'dirvish-quick-access))

(with-eval-after-load 'git-gutter
  (keymap-set hel-normal-state-map "]g" #'git-gutter:next-hunk)
  (keymap-set hel-normal-state-map "[g" #'git-gutter:previous-hunk))

(with-eval-after-load 'blamer
  (add-hook 'hel-insert-state-enter-hook #'my/disable-blamer-mode)
  (add-hook 'hel-normal-state-enter-hook #'blamer-mode))

(with-eval-after-load 'smerge-mode
  (keymap-set hel-normal-state-map "g s" #'smerge-next)
  (keymap-set hel-normal-state-map "g S" #'smerge-prev))

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
  (keymap-set hel-normal-state-map "g i" #'eglot-find-implementation)
  (keymap-set hel-normal-state-map "g r" #'xref-find-references)
  (keymap-set hel-normal-state-map "\\i" #'my/eglot-toggle-inlay-hints)
  (keymap-set hel-normal-state-map "\\l" #'eglot-code-actions))

(with-eval-after-load 'corfu
  (add-hook 'hel-insert-state-exit-hook (lambda () (corfu-quit))))

(with-eval-after-load 'flymake
  (keymap-set hel-normal-state-map "]d" #'flymake-goto-next-error)
  (keymap-set hel-normal-state-map "[d" #'flymake-goto-prev-error)
  (add-hook 'flymake-diagnostics-buffer-mode-hook
            (lambda () (when hel-local-mode (hel-motion-state 1)))))

(with-eval-after-load 'flymake-posframe
  (add-hook 'hel-normal-state-enter-hook #'my/toggle-flymake-posframe)
  (add-hook 'hel-insert-state-enter-hook #'my/toggle-flymake-posframe))

(with-eval-after-load 'eldoc-box
  (keymap-set hel-normal-state-map "\\b" #'my/toggle-eldoc-buffer)
  (keymap-set hel-normal-state-map "\\h" #'eldoc-box-help-at-point))

(with-eval-after-load 'pretty-ts-errors
  (keymap-set hel-normal-state-map "\\e" #'pretty-ts-errors-show-error-at-point))

(with-eval-after-load 'org
  (keymap-set hel-normal-state-map "\\o" #'org-mode)
  (keymap-set hel-normal-state-map "\\a" #'org-agenda))

(with-eval-after-load 'google-translate
  (keymap-set hel-normal-state-map "\\ t" #'google-translate-smooth-translate))

(with-eval-after-load 'magit
  (keymap-set magit-mode-map        ";" #'hel-collapse-selection)
  (keymap-set magit-status-mode-map "x" #'hel-expand-line-selection))

(with-eval-after-load 'copilot
  (add-hook 'hel-insert-state-enter-hook
            (lambda ()
              (setq blamer--block-render-p t)
              (blamer--clear-overlay)))
  (add-hook 'hel-insert-state-exit-hook
            (lambda ()
              (setq blamer--block-render-p nil)
              (copilot-clear-overlay)))

  (defun my/hel-copilot-show-overlay-depends-mode (completion uuid start end)
    "Suppress copilot overlay in normal state."
    (unless (bound-and-true-p hel-normal-state)
      (copilot--display-overlay-completion completion uuid start end)))
  (advice-add 'copilot-show-overlay :override #'my/hel-copilot-show-overlay-depends-mode))

(with-eval-after-load 'husky
  (keymap-set hel-normal-state-map "gd" #'husky-lsp-find-definition)
  (keymap-set hel-normal-state-map "%" #'husky-navigation-bounce-paren)
  (keymap-set hel-normal-state-map "g F" #'husky-lsp-avy-go-to-definition)
  (keymap-set hel-normal-state-map "g f" #'husky-lsp-avy-go-to-definition)
  (keymap-set hel-normal-state-map "g D" #'husky-buffers-side-husky-actions-find-definition)
  (keymap-set hel-normal-state-map "z r" #'husky-fold-open)
  (keymap-set hel-normal-state-map "z R" #'husky-fold-open-all)
  (keymap-set hel-normal-state-map "s-y" #'husky-lsp-copy-to-register-1)
  (keymap-set hel-normal-state-map "s-p" #'husky-lsp-paste-from-register-1)
  (keymap-set hel-normal-state-map "z A" #'husky-fold-toggle-all)
  (keymap-set hel-normal-state-map "z a" #'husky-fold-toggle)
  (keymap-set hel-normal-state-map "z j" #'husky-fold-next)
  (keymap-set hel-normal-state-map "z M" #'husky-fold-close-all)
  (keymap-set hel-normal-state-map "z k" #'husky-fold-previous))

(with-eval-after-load 'better-jumper
  (advice-add 'hel-forward-word-start :around #'my/better-jump-preserve-pos-advice))

(provide 'kaizen-bindings-hel)
;;; bindings/hel.el ends here

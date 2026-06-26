;;; bindings/helixel.el --- helixel (Helix-style) modal editing scheme -*- lexical-binding: t; -*-
(when (featurep 'kaizen-bindings-helixel)
  (user-error "kaizen-bindings-helixel already loaded"))

(require 'kaizen nil t)

(use-package helixel
  :ensure (:host github :repo "jixiuf/helixel-mode" :files (:defaults "**") :wait t)
  :demand t
  :config
  (defun kaizen/helixel-disable-in-minibuffer ()
    (when (bound-and-true-p helixel-global-mode)
      (dolist (sel '(helixel-normal-state helixel-insert-state
                     helixel-motion-state helixel-visual-state))
        (when (and (boundp sel) (symbol-value sel))
          (funcall sel -1)))))
  (add-hook 'minibuffer-setup-hook #'kaizen/helixel-disable-in-minibuffer 100)
  (defun kaizen/helixel-apply-cursor ()
    (setq cursor-type
          (pcase helixel--current-state
            ('insert 'bar)
            ('normal 'box)
            ('motion 'hollow)
            ('visual 'hollow)
            (_ cursor-type))))
  (add-hook 'helixel-state-change-hook #'kaizen/helixel-apply-cursor)

  (dolist (state '(normal motion))
    (helixel-define-key state (kbd "C-o") #'better-jumper-jump-backward)
    (helixel-define-key state (kbd "C-i") #'better-jumper-jump-forward)))

(dolist (map (list minibuffer-local-map
                   minibuffer-local-ns-map
                   minibuffer-local-completion-map
                   minibuffer-local-must-match-map
                   read-expression-map))
  (keymap-set map "<escape>" #'abort-recursive-edit))

(defun kaizen/helixel-G (arg)
  "Go to line ARG, or end of buffer if no ARG."
  (interactive "P")
  (if arg (goto-line (prefix-numeric-value arg)) (helixel-go-end-buffer)))

(defun kaizen/helixel-insert-at-indentation ()
  "Move to the first non-blank character, then switch to Insert state."
  (interactive)
  (back-to-indentation)
  (call-interactively #'helixel-insert))

(defun kaizen/helixel-change ()
  "Delete region without touching `kill-ring', then switch to Insert state."
  (interactive "*")
  (if (use-region-p)
      (let ((linewise? (eq (helixel--region-type) 'line))
            (vislines? (eq (helixel--region-type) 'rect)))
        (helixel-delete-selection t)
        (cond (linewise?
               (newline)
               (backward-char)
               (indent-according-to-mode))
              (vislines?
               (insert " ")
               (backward-char))))
    (unless (bolp)
      (delete-char -1)))
  (call-interactively #'helixel-insert))

(defvar-keymap kaizen/helixel-help-map
  "f" #'helpful-function
  "F" #'describe-face
  "v" #'helpful-variable
  "k" #'describe-key
  "t" #'load-theme)

(defun kaizen/helixel-avy-select-word ()
  "Jump to word with avy, then select it (helixel-aware)."
  (interactive)
  (call-interactively #'avy-goto-word-1)
  (helixel-mark-inner-WORD 1))

(defun kaizen/helixel-search-or-next ()
  "If searching, go to next match. Otherwise search for word under cursor."
  (interactive)
  (if (bound-and-true-p helixel--active-search)
      (call-interactively #'helixel-search-repeat-next)
    (call-interactively #'helixel-search-at-point-next)))

(defvar-keymap kaizen/helixel-vcs-map
  "l" #'majutsu
  "h" #'git-timemachine)

(defvar-keymap kaizen/helixel-bookmark-map
  "m" #'bm-toggle
  "l" #'bm-show)

(defvar-keymap kaizen/helixel-org-link-map
  "s" #'org-store-link
  "l" #'org-insert-link
  "t" #'org-toggle-link-display
  "d" #'org-toggle-link-display)

(defvar-keymap kaizen/helixel-window-map
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

  (dolist (state '(normal motion))
    (helixel-define-key state left  #'helixel-backward-char)
    (helixel-define-key state down  #'helixel-next-line)
    (helixel-define-key state up    #'helixel-previous-line)
    (helixel-define-key state right #'helixel-forward-char)
    (helixel-define-key state line-start #'helixel-go-beginning-line)
    (helixel-define-key state line-end   #'helixel-go-end-line))

  (helixel-define-key 'normal ins    #'helixel-insert-after)
  (helixel-define-key 'normal (upcase ins) #'kaizen/helixel-insert-at-indentation)
  (helixel-define-key 'normal "k"   #'kaizen/helixel-search-or-next)
  (helixel-define-key 'normal "r"   #'helixel-replace)
  (helixel-define-key 'normal "j"   #'helixel-forward-word-start)
  (helixel-define-key 'normal "J"   #'helixel-forward-WORD-start)
  (helixel-define-key 'normal "c"   #'kaizen/helixel-change)
  (helixel-define-key 'normal "q"   #'deactivate-mark)
  (helixel-define-key 'normal "G"   #'kaizen/helixel-G)
  (helixel-define-key 'normal "N"   #'my/copy-with-ai-context)
  (helixel-define-key 'normal (kbd "C-:") #'query-replace-regexp)
  (helixel-define-key 'normal "/"   #'helixel-search-forward)

  (helixel-define-key 'motion (upcase ins) #'back-to-indentation)

  (define-key helixel-normal-map (kbd "C-n") #'flymake-goto-next-error)
  (define-key helixel-normal-map (kbd "C-e") #'flymake-goto-prev-error)
  (helixel-define-key 'normal "] d" #'flymake-goto-next-error)
  (helixel-define-key 'normal "[ d" #'flymake-goto-prev-error)

  (keymap-set mode-specific-map "b" kaizen/helixel-bookmark-map)
  (keymap-set mode-specific-map "h" kaizen/helixel-help-map)
  (keymap-set mode-specific-map "v" kaizen/helixel-vcs-map)
  (keymap-set mode-specific-map "w" kaizen/helixel-window-map)

  (global-set-key (kbd "s-c") #'helixel-kill-ring-save)

  (dolist (mode '(prog-mode text-mode conf-mode fundamental-mode))
    (add-to-list 'helixel-major-mode-default-states (cons mode 'normal)))

  (dolist (mode '(elpaca-info-mode flymake-diagnostics-buffer-mode
                                   flycheck-error-list-mode magit-process-mode
                                   compilation-mode helpful-mode help-mode
                                   debug-mode debugger-mode
                                   grep-mode))
    (add-to-list 'helixel-major-mode-default-states (cons mode 'motion)))

  (dolist (mode '(ediff-mode ediff-meta-mode))
    (add-to-list 'helixel-major-mode-default-states (cons mode 'motion)))
  (dolist (mode '(ediff-mode ediff-meta-mode))
    (add-to-list 'helixel-motion-parent-excluded-modes mode))

  (add-to-list 'helixel-major-mode-default-states '(org-agenda-mode . normal)))

(defun kaizen/helixel-bind-leader ()
  "Bind SPC to the kaizen leader (`mode-specific-map') in helixel states.
Done after `helixel-mode' so helixel's own space-map init can't override it."
  (define-key helixel-normal-map " " mode-specific-map)
  (define-key helixel-motion-map " " mode-specific-map))

(with-eval-after-load 'org-agenda
  (helixel-define-key 'normal "<escape>" #'org-agenda-quit 'org-agenda-mode)
  (helixel-define-key 'normal "SPC" mode-specific-map 'org-agenda-mode)
  (helixel-define-key 'normal "q" #'org-agenda-quit 'org-agenda-mode)
  (helixel-define-key 'normal "g" #'org-agenda-redo 'org-agenda-mode)
  (helixel-define-key 'normal "." #'org-agenda-goto-today 'org-agenda-mode)
  (helixel-define-key 'normal "t" #'org-agenda-todo 'org-agenda-mode)
  (helixel-define-key 'normal "s" #'org-agenda-schedule 'org-agenda-mode)
  (helixel-define-key 'normal "d" #'org-agenda-deadline 'org-agenda-mode)
  (helixel-define-key 'normal ":" #'org-agenda-set-tags 'org-agenda-mode)
  (helixel-define-key 'normal "/" #'org-agenda-filter 'org-agenda-mode)
  (helixel-define-key 'normal "v" #'org-agenda-view-mode-dispatch 'org-agenda-mode)
  (helixel-define-key 'normal "TAB" #'org-agenda-goto 'org-agenda-mode)
  (helixel-define-key 'normal "RET" #'org-agenda-switch-to 'org-agenda-mode)
  (helixel-define-key 'normal "f" #'avy-goto-word-1 'org-agenda-mode)

  (let ((down (or (bound-and-true-p kaizen/nav-down) "n"))
        (up   (or (bound-and-true-p kaizen/nav-up) "e"))
        (left (or (bound-and-true-p kaizen/nav-left) "h"))
        (right (or (bound-and-true-p kaizen/nav-right) "i")))
    (helixel-define-key 'normal down #'org-agenda-next-line 'org-agenda-mode)
    (helixel-define-key 'normal up #'org-agenda-previous-line 'org-agenda-mode)
    (helixel-define-key 'normal left #'org-agenda-earlier 'org-agenda-mode)
    (helixel-define-key 'normal right #'org-agenda-later 'org-agenda-mode)
    (helixel-define-key 'normal (upcase down) #'org-agenda-next-item 'org-agenda-mode)
    (helixel-define-key 'normal (upcase up) #'org-agenda-previous-item 'org-agenda-mode))

  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-agenda-mode)
        (when (fboundp 'helixel-normal-state)
          (helixel-normal-state 1))))))

;; Package integrations — with-eval-after-load inside :config
;; helixel is guaranteed loaded here, packages may load later
(with-eval-after-load 'avy
  (helixel-define-key 'normal "f" #'kaizen/helixel-avy-select-word)
  (helixel-define-key 'normal "\\ f" #'avy-goto-char-timer))

(with-eval-after-load 'bm
  (helixel-define-key 'normal "] m" #'bm-next)
  (helixel-define-key 'normal "[ m" #'bm-previous)
  (helixel-define-key 'normal "SPC b m" #'bm-toggle)
  (helixel-define-key 'normal "SPC b l" #'bm-show))

(with-eval-after-load 'undo-fu
  (helixel-define-key 'normal "u" #'undo-fu-only-undo)
  (helixel-define-key 'normal "U" #'undo-fu-only-redo))

(with-eval-after-load 'persistent-kmacro
  (helixel-define-key 'normal "#" #'persistent-kmacro-apply))

(with-eval-after-load 'apheleia
  (helixel-define-key 'normal "\\ p" #'apheleia-format-buffer))

(with-eval-after-load 'consult
  (helixel-define-key 'normal "SPC b a" #'consult-buffer)
  (helixel-define-key 'normal "SPC b b" #'consult-project-buffer))

(helixel-define-key 'normal "SPC f f" #'project-find-file)

(with-eval-after-load 'dirvish
  (helixel-define-key 'normal "g f" #'dirvish-quick-access))

(dolist (state '(normal motion))
  (helixel-define-key state "SPC g r" #'git-gutter:revert-hunk)
  (helixel-define-key state "] g" #'git-gutter:next-hunk)
  (helixel-define-key state "[ g" #'git-gutter:previous-hunk))

(with-eval-after-load 'blamer
  (add-hook 'helixel-state-change-hook
            (lambda ()
              (cond
               ((eq helixel--current-state 'insert) (my/disable-blamer-mode))
               ((eq helixel--current-state 'normal) (blamer-mode))))))

(with-eval-after-load 'smerge-mode
  (helixel-define-key 'normal "g s" #'smerge-next)
  (helixel-define-key 'normal "g S" #'smerge-prev))

(with-eval-after-load 'ediff
  (let ((down (or (bound-and-true-p kaizen/nav-down) "n"))
        (up   (or (bound-and-true-p kaizen/nav-up) "e")))
    (helixel-define-key 'motion down #'ediff-next-difference 'ediff-mode)
    (helixel-define-key 'motion up #'ediff-previous-difference 'ediff-mode))
  (helixel-define-key 'motion "<escape>" #'ediff-quit 'ediff-mode)
  (add-hook 'ediff-cleanup-hook
            (lambda ()
              (when (and (boundp 'helixel-global-mode) helixel-global-mode)
                (when (fboundp 'helixel-normal-state)
                  (helixel-normal-state 1))))))

(with-eval-after-load 'eglot
  (helixel-define-key 'normal "g i" #'eglot-find-implementation)
  (helixel-define-key 'normal "g r" #'xref-find-references)
  (helixel-define-key 'normal "\\ i" #'my/eglot-toggle-inlay-hints)
  (helixel-define-key 'normal "SPC l a" #'eglot-code-actions)
  (helixel-define-key 'normal "SPC l r" #'eglot-rename)
  (helixel-define-key 'normal "SPC l h" #'eldoc)
  (helixel-define-key 'normal "SPC l f" #'eglot-format-buffer)
  (helixel-define-key 'normal "SPC l d" #'flymake-show-buffer-diagnostics))

(with-eval-after-load 'corfu
  (add-hook 'helixel-state-change-hook
            (lambda ()
              (unless (eq helixel--current-state 'insert)
                (when (fboundp 'corfu-quit)
                  (ignore-errors (corfu-quit)))))))

(with-eval-after-load 'flymake-posframe
  (add-hook 'helixel-state-change-hook
            (lambda ()
              (when (memq helixel--current-state '(normal insert))
                (my/toggle-flymake-posframe)))))

(with-eval-after-load 'eldoc-box
  (helixel-define-key 'normal "\\ b" #'my/toggle-eldoc-buffer)
  (helixel-define-key 'normal "\\ h" #'eldoc-box-help-at-point))

(with-eval-after-load 'pretty-ts-errors
  (helixel-define-key 'normal "\\ e" #'pretty-ts-errors-show-error-at-point))

(with-eval-after-load 'org
  (keymap-set mode-specific-map "m l" kaizen/helixel-org-link-map)
  (helixel-define-key 'normal "\\ o" #'org-mode)
  (helixel-define-key 'normal "\\ a" #'org-agenda)
  (helixel-define-key 'normal "SPC m l l" #'org-insert-link)
  (helixel-define-key 'normal "SPC m l t" #'org-toggle-link-display)
  (helixel-define-key 'normal "SPC m l d" #'org-toggle-link-display)
  (helixel-define-key 'normal "SPC m l s" #'org-store-link))

(with-eval-after-load 'google-translate
  (helixel-define-key 'normal "\\ t" #'google-translate-smooth-translate))

(with-eval-after-load 'magit
  (keymap-set magit-mode-map ";" (if (fboundp 'helixel-action-cycle)
                                     #'helixel-action-cycle
                                   #'ignore))
  (keymap-set magit-status-mode-map "x"
              (if (fboundp 'helixel-select-line)
                  #'helixel-select-line
                #'ignore)))

(with-eval-after-load 'copilot
  (add-hook 'helixel-state-change-hook
            (lambda ()
              (cond
               ((eq helixel--current-state 'insert)
                (setq blamer--block-render-p t)
                (when (fboundp 'blamer--clear-overlay)
                  (blamer--clear-overlay)))
               ((eq helixel--current-state 'normal)
                (setq blamer--block-render-p nil)
                (when (fboundp 'copilot-clear-overlay)
                  (copilot-clear-overlay))))))
  (advice-add 'copilot-show-overlay :override
              (lambda (completion uuid start end)
                (unless (bound-and-true-p helixel-normal-state)
                  (copilot--display-overlay-completion completion uuid start end)))))

(with-eval-after-load 'husky
  (helixel-define-key 'normal "g d" #'husky-lsp-find-definition)
  (helixel-define-key 'normal "g D" #'husky-buffers-side-husky-actions-find-definition)
  (helixel-define-key 'normal "%" #'husky-navigation-bounce-paren)
  (helixel-define-key 'normal "g F" #'husky-lsp-avy-go-to-definition)
  (helixel-define-key 'normal "g f" #'husky-lsp-avy-go-to-definition)
  (helixel-define-key 'normal "s-y" #'husky-lsp-copy-to-register-1)
  (helixel-define-key 'normal "s-p" #'husky-lsp-paste-from-register-1))

(with-eval-after-load 'better-jumper
  (advice-add 'helixel-forward-word-start :around
              #'my/better-jump-preserve-pos-advice))

(let ((fold-next (concat "z " (or (bound-and-true-p kaizen/nav-down) "j")))
      (fold-prev (concat "z " (or (bound-and-true-p kaizen/nav-up) "k"))))
  (helixel-define-key 'normal "z r" #'husky-fold-open)
  (helixel-define-key 'normal "z R" #'husky-fold-open-all)
  (helixel-define-key 'normal "z A" #'husky-fold-toggle-all)
  (helixel-define-key 'normal "z a" #'husky-fold-toggle)
  (helixel-define-key 'normal fold-next #'husky-fold-next)
  (helixel-define-key 'normal "z M" #'husky-fold-close-all)
  (helixel-define-key 'normal fold-prev #'husky-fold-previous))

(helixel-mode)
(kaizen/helixel-bind-leader)

(provide 'kaizen-bindings-helixel)
;;; bindings/helixel.el ends here
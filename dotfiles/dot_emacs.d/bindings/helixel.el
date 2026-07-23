;;; bindings/helixel.el --- helixel (Helix-style) modal editing scheme -*- lexical-binding: t; -*-

(when (featurep 'kaizen-bindings-helixel)
  (user-error "kaizen-bindings-helixel already loaded"))

(require 'kaizen nil t)

(use-package helixel
  :ensure (:host github :repo "jixiuf/helixel-mode" :files (:defaults "**") :wait t)
  :demand t
  :config
  (defun kaizen/enable-helixel-normal-state-in-buffer (&optional buffer)
    "Enable Helixel normal state in BUFFER if possible."
    (when (fboundp 'helixel-normal-state)
      (with-current-buffer (or buffer (current-buffer))
        (unless (or (minibufferp)
                    (bound-and-true-p helixel-normal-state)
                    (bound-and-true-p helixel-insert-state)
                    (bound-and-true-p helixel-motion-state)
                    (bound-and-true-p helixel-visual-state))
          (helixel-normal-state 1)))))

  ;; Scratch usually uses `lisp-interaction-mode`.
  (add-hook 'lisp-interaction-mode-hook
            #'kaizen/enable-helixel-normal-state-in-buffer)

  ;; Messages buffer has its own major mode in modern Emacs.
  (add-hook 'messages-buffer-mode-hook
            #'kaizen/enable-helixel-normal-state-in-buffer)

  ;; These buffers may already exist before hooks are installed.
  (add-hook
   'emacs-startup-hook
   (lambda ()
     (dolist (buffer-name '("*scratch*" "*Messages*"))
       (when-let ((buffer (get-buffer buffer-name)))
         (kaizen/enable-helixel-normal-state-in-buffer buffer)))))

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
    (helixel-define-key state (kbd "C-S-o") #'better-jumper-jump-forward))

  (helixel-define-key 'insert (kbd "TAB") #'indent-for-tab-command))

(dolist (map (list minibuffer-local-map
                   minibuffer-local-ns-map
                   minibuffer-local-completion-map
                   minibuffer-local-must-match-map
                   read-expression-map))
  (keymap-set map "<escape>" #'abort-recursive-edit))

(defun kaizen/helixel-G (arg)
  "Go to line ARG, or end of buffer if no ARG."
  (interactive "P")
  (if arg
      (goto-line (prefix-numeric-value arg))
    (helixel-go-end-buffer)))

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
        (cond
         (linewise?
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
  "Jump to word with avy, then select it."
  (interactive)
  (call-interactively #'avy-goto-word-1)
  (helixel-mark-inner-word 1))

(defun kaizen/helixel-search-or-next ()
  "Search active selection first, otherwise repeat or search word at point."
  (interactive)
  (cond
   ((use-region-p)
    (helixel-search--from-region 'forward))
   ((bound-and-true-p helixel--active-search)
    (call-interactively #'helixel-search-repeat-next))
   (t
    (call-interactively #'helixel-search-at-point-next))))

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

(defun kaizen/helixel-bind-leader ()
  "Bind SPC to the kaizen leader (`mode-specific-map') in Helixel states."
  (define-key helixel-normal-map (kbd "SPC") mode-specific-map)
  (define-key helixel-motion-map (kbd "SPC") mode-specific-map))

;; Attach the leader before any SPC bindings.
(kaizen/helixel-bind-leader)

;;; Default states

(defun kaizen/helixel-set-default-state (mode state)
  "Set Helixel default STATE for MODE without duplicating entries."
  (setq helixel-major-mode-default-states
        (assq-delete-all mode helixel-major-mode-default-states))
  (add-to-list 'helixel-major-mode-default-states
               (cons mode state)))

(defvar kaizen/helixel-normal-modes
  '(prog-mode
    text-mode
    conf-mode
    fundamental-mode
    lisp-interaction-mode
    emacs-lisp-mode
    ghostel-mode
    messages-buffer-mode
    org-agenda-mode)
  "Modes where Helixel should start in normal state.")

(defvar kaizen/helixel-motion-modes
  '(special-mode
    dired-mode
    elpaca-info-mode
    flymake-diagnostics-buffer-mode
    flycheck-error-list-mode
    magit-mode
    magit-status-mode
    magit-log-mode
    magit-diff-mode
    magit-process-mode
    majutsu-mode
    majutsu-log-mode
    majutsu-status-mode
    compilation-mode
    helpful-mode
    help-mode
    debug-mode
    debugger-mode
    grep-mode
    ediff-mode
    ediff-meta-mode)
  "Modes where Helixel should start in motion state.")

(dolist (mode kaizen/helixel-normal-modes)
  (kaizen/helixel-set-default-state mode 'normal))

(dolist (mode kaizen/helixel-motion-modes)
  (kaizen/helixel-set-default-state mode 'motion))

;; Ediff should use its own motion bindings instead of inheriting the generic
;; Helixel motion parent map.
(dolist (mode '(ediff-mode ediff-meta-mode))
  (add-to-list 'helixel-motion-parent-excluded-modes mode))

;;; Layout-aware navigation bindings

(let* ((left     (or (bound-and-true-p kaizen/nav-left)   "h"))
       (down     (or (bound-and-true-p kaizen/nav-down)   "n"))
       (up       (or (bound-and-true-p kaizen/nav-up)     "e"))
       (right    (or (bound-and-true-p kaizen/nav-right)  "i"))
       (ins      (or (bound-and-true-p kaizen/nav-insert) "l"))
       (line-end (or (bound-and-true-p kaizen/line-end)   "$")))

  ;; Generic navigation for normal/motion buffers.
  ;; Ediff is excluded from generic motion parent above.
  (dolist (state '(normal motion))
    (helixel-define-key state (kbd left)     #'helixel-backward-char)
    (helixel-define-key state (kbd down)     #'helixel-next-line)
    (helixel-define-key state (kbd up)       #'helixel-previous-line)
    (helixel-define-key state (kbd right)    #'helixel-forward-char)
    (helixel-define-key state (kbd line-end) #'helixel-go-end-line))

  ;; Count prefix: bind 0-9 to `digit-argument'.
  (dotimes (i 10)
    (helixel-define-key 'normal (number-to-string i) #'digit-argument))

  (helixel-define-key 'normal (kbd ins)          #'helixel-insert)
  (helixel-define-key 'normal (kbd (upcase ins)) #'kaizen/helixel-insert-at-indentation)
  (helixel-define-key 'normal "k"                #'kaizen/helixel-search-or-next)
  (helixel-define-key 'normal "K"                #'helixel-search-repeat-reverse)
  (helixel-define-key 'normal "r"                #'helixel-replace)
  (helixel-define-key 'normal "j"                #'helixel-forward-word-start)
  (helixel-define-key 'normal "J"                #'helixel-forward-WORD-start)
  (helixel-define-key 'normal "c"                #'kaizen/helixel-change)
  (helixel-define-key 'normal "q"                #'deactivate-mark)
  (helixel-define-key 'normal "G"                #'kaizen/helixel-G)
  (helixel-define-key 'normal "N"                #'my/copy-with-ai-context)
  (helixel-define-key 'normal (kbd "C-:")        #'query-replace-regexp)
  (helixel-define-key 'normal "/"                #'helixel-search-forward)

  (helixel-define-key 'motion (kbd (upcase ins)) #'back-to-indentation)

  (define-key helixel-normal-map (kbd "C-n") #'flymake-goto-next-error)
  (define-key helixel-normal-map (kbd "C-e") #'flymake-goto-prev-error)
  (helixel-define-key 'normal (kbd "] d") #'flymake-goto-next-error)
  (helixel-define-key 'normal (kbd "[ d") #'flymake-goto-prev-error)

  (keymap-set mode-specific-map "b" kaizen/helixel-bookmark-map)
  (keymap-set mode-specific-map "h" kaizen/helixel-help-map)
  (keymap-set mode-specific-map "v" kaizen/helixel-vcs-map)
  (keymap-set mode-specific-map "w" kaizen/helixel-window-map)

  (global-set-key (kbd "s-c") #'helixel-kill-ring-save))

(with-eval-after-load 'dired
  (helixel-define-key 'motion "-" #'dired-up-directory 'dired-mode)
  (helixel-define-key 'motion "h" #'dired-up-directory 'dired-mode))

(with-eval-after-load 'org-agenda
  (helixel-define-key 'normal (kbd "<escape>") #'org-agenda-quit 'org-agenda-mode)
  (helixel-define-key 'normal (kbd "SPC") mode-specific-map 'org-agenda-mode)
  (helixel-define-key 'normal "q" #'org-agenda-quit 'org-agenda-mode)
  (helixel-define-key 'normal "g" #'org-agenda-redo 'org-agenda-mode)
  (helixel-define-key 'normal "." #'org-agenda-goto-today 'org-agenda-mode)
  (helixel-define-key 'normal "t" #'org-agenda-todo 'org-agenda-mode)
  (helixel-define-key 'normal "s" #'org-agenda-schedule 'org-agenda-mode)
  (helixel-define-key 'normal "d" #'org-agenda-deadline 'org-agenda-mode)
  (helixel-define-key 'normal ":" #'org-agenda-set-tags 'org-agenda-mode)
  (helixel-define-key 'normal "/" #'org-agenda-filter 'org-agenda-mode)
  (helixel-define-key 'normal "v" #'org-agenda-view-mode-dispatch 'org-agenda-mode)
  (helixel-define-key 'normal (kbd "TAB") #'org-agenda-goto 'org-agenda-mode)
  (helixel-define-key 'normal (kbd "RET") #'org-agenda-switch-to 'org-agenda-mode)
  (helixel-define-key 'normal "f" #'avy-goto-word-1 'org-agenda-mode)

  (let ((down  (or (bound-and-true-p kaizen/nav-down)  "n"))
        (up    (or (bound-and-true-p kaizen/nav-up)    "e"))
        (left  (or (bound-and-true-p kaizen/nav-left)  "h"))
        (right (or (bound-and-true-p kaizen/nav-right) "i")))
    (helixel-define-key 'normal (kbd down)          #'org-agenda-next-line 'org-agenda-mode)
    (helixel-define-key 'normal (kbd up)            #'org-agenda-previous-line 'org-agenda-mode)
    (helixel-define-key 'normal (kbd left)          #'org-agenda-earlier 'org-agenda-mode)
    (helixel-define-key 'normal (kbd right)         #'org-agenda-later 'org-agenda-mode)
    (helixel-define-key 'normal (kbd (upcase down)) #'org-agenda-next-item 'org-agenda-mode)
    (helixel-define-key 'normal (kbd (upcase up))   #'org-agenda-previous-item 'org-agenda-mode)))

;;; Package integrations

(with-eval-after-load 'avy
  (helixel-define-key 'normal "f" #'kaizen/helixel-avy-select-word)
  (helixel-define-key 'normal (kbd "\\ f") #'avy-goto-char-timer))

(with-eval-after-load 'bm
  (helixel-define-key 'normal (kbd "] m") #'bm-next)
  (helixel-define-key 'normal (kbd "[ m") #'bm-previous)
  (helixel-define-key 'normal (kbd "SPC b m") #'bm-toggle)
  (helixel-define-key 'normal (kbd "SPC b l") #'bm-show))

(with-eval-after-load 'undo-fu
  (helixel-define-key 'normal "u" #'undo-fu-only-undo)
  (helixel-define-key 'normal "U" #'undo-fu-only-redo))

(with-eval-after-load 'persistent-kmacro
  (helixel-define-key 'normal "#" #'persistent-kmacro-apply))

(with-eval-after-load 'apheleia
  (helixel-define-key 'normal (kbd "\\ p") #'apheleia-format-buffer))

(with-eval-after-load 'consult
  (helixel-define-key 'normal (kbd "SPC b a") #'consult-buffer)
  (helixel-define-key 'normal (kbd "SPC b b") #'consult-project-buffer))

(helixel-define-key 'normal (kbd "SPC f f") #'project-find-file)

(with-eval-after-load 'dirvish
  (helixel-define-key 'normal (kbd "g f") #'dirvish-quick-access))

(dolist (state '(normal motion))
  (helixel-define-key state (kbd "SPC g r") #'git-gutter:revert-hunk)
  (helixel-define-key state (kbd "] g") #'git-gutter:next-hunk)
  (helixel-define-key state (kbd "[ g") #'git-gutter:previous-hunk))

(with-eval-after-load 'blamer
  (add-hook 'helixel-state-change-hook
            (lambda ()
              (cond
               ((eq helixel--current-state 'insert)
                (my/disable-blamer-mode))
               ((eq helixel--current-state 'normal)
                (blamer-mode))))))

(with-eval-after-load 'smerge-mode
  (helixel-define-key 'normal (kbd "g s") #'smerge-next)
  (helixel-define-key 'normal (kbd "g S") #'smerge-prev))

;;; Ediff integration

(defun kaizen/helixel-ediff-bindings ()
  "Setup layout-aware Ediff bindings for Helixel motion state."
  (let* ((down (or (bound-and-true-p kaizen/nav-down) "n"))
         (up   (or (bound-and-true-p kaizen/nav-up)   "e"))
         ;; Bind both layout keys and explicit n/e fallbacks.
         ;; This fixes cases where `kaizen/nav-up' is not currently \"e\".
         (next-keys (delete-dups (list down "n")))
         (prev-keys (delete-dups (list up "e" "p"))))

    (dolist (key next-keys)
      (when (and (stringp key)
                 (> (length key) 0))
        (when (boundp 'ediff-mode-map)
          (keymap-set ediff-mode-map key #'ediff-next-difference))
        (helixel-define-key 'motion (kbd key)
                            #'ediff-next-difference
                            'ediff-mode)))

    (dolist (key prev-keys)
      (when (and (stringp key)
                 (> (length key) 0))
        (when (boundp 'ediff-mode-map)
          (keymap-set ediff-mode-map key #'ediff-previous-difference))
        (helixel-define-key 'motion (kbd key)
                            #'ediff-previous-difference
                            'ediff-mode)))

    ;; Keep standard Ediff-ish controls.
    (helixel-define-key 'motion (kbd "SPC") #'ediff-next-difference 'ediff-mode)
    (helixel-define-key 'motion (kbd "S-SPC") #'ediff-previous-difference 'ediff-mode)
    (helixel-define-key 'motion (kbd "<backspace>") #'ediff-previous-difference 'ediff-mode)
    (helixel-define-key 'motion (kbd "<delete>") #'ediff-previous-difference 'ediff-mode)
    (helixel-define-key 'motion (kbd "?") #'ediff-toggle-help 'ediff-mode)
    (helixel-define-key 'motion (kbd "q") #'ediff-quit 'ediff-mode)
    (helixel-define-key 'motion (kbd "<escape>") #'ediff-quit 'ediff-mode)))

(with-eval-after-load 'ediff
  (defvar-local kaizen/helixel-ediff-motion-map nil
    "Buffer-local overriding map for `helixel-motion-state' in Ediff buffers.")

  (defun kaizen/helixel-ediff--valid-key-p (key)
    "Return non-nil when KEY is a non-empty string."
    (and (stringp key)
         (> (length key) 0)))

  (defun kaizen/helixel-ediff--control-buffer ()
    "Return current Ediff control buffer, if available."
    (cond
     ((and (boundp 'ediff-control-buffer)
           (buffer-live-p ediff-control-buffer))
      ediff-control-buffer)
     ((derived-mode-p 'ediff-mode)
      (current-buffer))
     (t
      nil)))

  (defun kaizen/helixel-ediff-setup-motion-map ()
    "Install Helixel-like motion keys in the Ediff control buffer."
    (let* ((buffer (and (fboundp 'kaizen/helixel-ediff--control-buffer)
                        (kaizen/helixel-ediff--control-buffer))))
      (when buffer
        (with-current-buffer buffer
          (let* ((down (or (and (boundp 'kaizen/nav-down) kaizen/nav-down) "n"))
                 (up   (or (and (boundp 'kaizen/nav-up) kaizen/nav-up) "e"))
                 (next-keys (delete-dups (delq nil (list down "n" "j" "SPC"))))
                 (prev-keys (delete-dups
                             (delq nil
                                   (list up "e" "k" "p" "S-SPC"
                                         "<backspace>" "<delete>"))))
                 (map (make-sparse-keymap)))

            (dolist (key next-keys)
              (when (kaizen/helixel-ediff--valid-key-p key)
                (define-key map (kbd key) #'ediff-next-difference)
                (when (fboundp 'helixel-define-key)
                  (helixel-define-key
                   'motion
                   (kbd key)
                   #'ediff-next-difference
                   'ediff-mode))))

            (dolist (key prev-keys)
              (when (kaizen/helixel-ediff--valid-key-p key)
                (define-key map (kbd key) #'ediff-previous-difference)
                (when (fboundp 'helixel-define-key)
                  (helixel-define-key
                   'motion
                   (kbd key)
                   #'ediff-previous-difference
                   'ediff-mode))))

            (define-key map (kbd "?") #'ediff-toggle-help)
            (define-key map (kbd "q") #'ediff-quit)
            (define-key map (kbd "<escape>") #'ediff-quit)

            (setq-local kaizen/helixel-ediff-motion-map map)

            (setq-local minor-mode-overriding-map-alist
                        (assq-delete-all
                         'helixel-motion-state
                         minor-mode-overriding-map-alist))

            (push `(helixel-motion-state . ,kaizen/helixel-ediff-motion-map)
                  minor-mode-overriding-map-alist)

            (when (fboundp 'helixel-motion-state)
              (helixel-motion-state 1)))))))

  ;; Ediff can rebuild its control buffer/keymap during setup, so install the
  ;; override from several Ediff lifecycle hooks.
  (add-hook 'ediff-mode-hook #'kaizen/helixel-ediff-setup-motion-map)
  (add-hook 'ediff-startup-hook #'kaizen/helixel-ediff-setup-motion-map)
  (add-hook 'ediff-keymap-setup-hook #'kaizen/helixel-ediff-setup-motion-map)

  ;; If this file is reloaded while Ediff is already open, patch existing
  ;; control buffers immediately.
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'ediff-mode)
        (kaizen/helixel-ediff-setup-motion-map))))

  (add-hook 'ediff-cleanup-hook
            (lambda ()
              (when (fboundp 'helixel-normal-state)
                (helixel-normal-state 1)))))

(with-eval-after-load 'eglot
  (helixel-define-key 'normal (kbd "g i") #'eglot-find-implementation)
  (helixel-define-key 'normal (kbd "g r") #'xref-find-references)
  (helixel-define-key 'normal (kbd "\\ i") #'my/eglot-toggle-inlay-hints)
  (helixel-define-key 'normal (kbd "SPC l a") #'eglot-code-actions)
  (helixel-define-key 'normal (kbd "SPC l r") #'eglot-rename)
  (helixel-define-key 'normal (kbd "SPC l h") #'eldoc)
  (helixel-define-key 'normal (kbd "SPC l f") #'eglot-format-buffer)
  (helixel-define-key 'normal (kbd "SPC l d") #'flymake-show-buffer-diagnostics))

(with-eval-after-load 'corfu
  (add-hook 'helixel-normal-state-hook
            (lambda ()
              (when (fboundp 'corfu-quit)
                (ignore-errors (corfu-quit))))))

(with-eval-after-load 'flymake-posframe
  (add-hook 'helixel-state-change-hook
            (lambda ()
              (when (memq helixel--current-state '(normal insert))
                (my/toggle-flymake-posframe)))))

(with-eval-after-load 'eldoc-box
  (helixel-define-key 'normal (kbd "\\ b") #'my/toggle-eldoc-buffer)
  (helixel-define-key 'normal (kbd "\\ h") #'eldoc-box-help-at-point))

(with-eval-after-load 'pretty-ts-errors
  (helixel-define-key 'normal (kbd "\\ e") #'pretty-ts-errors-show-error-at-point))

(with-eval-after-load 'org
  (keymap-set mode-specific-map "m l" kaizen/helixel-org-link-map)
  (helixel-define-key 'normal (kbd "\\ o") #'org-mode)
  (helixel-define-key 'normal (kbd "\\ a") #'org-agenda)
  (helixel-define-key 'normal (kbd "SPC m l l") #'org-insert-link)
  (helixel-define-key 'normal (kbd "SPC m l t") #'org-toggle-link-display)
  (helixel-define-key 'normal (kbd "SPC m l d") #'org-toggle-link-display)
  (helixel-define-key 'normal (kbd "SPC m l s") #'org-store-link))

(with-eval-after-load 'google-translate
  (helixel-define-key 'normal (kbd "\\ t") #'google-translate-smooth-translate))

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

(with-eval-after-load 'golden-ratio-scroll-screen
  (define-key global-map (kbd "C-d") #'golden-ratio-scroll-screen-up)
  (define-key global-map (kbd "C-u") #'golden-ratio-scroll-screen-down))

(with-eval-after-load 'husky
  (helixel-define-key 'normal (kbd "g d") #'husky-lsp-find-definition)
  (helixel-define-key 'normal (kbd "g D") #'husky-buffers-side-husky-actions-find-definition)
  (helixel-define-key 'normal "%" #'husky-navigation-bounce-paren)
  (helixel-define-key 'normal (kbd "g F") #'husky-lsp-avy-go-to-definition)
  (helixel-define-key 'normal (kbd "g f") #'husky-lsp-avy-go-to-definition)
  (helixel-define-key 'normal (kbd "s-y") #'husky-lsp-copy-to-register-1)
  (helixel-define-key 'normal (kbd "s-p") #'husky-lsp-paste-from-register-1))

(with-eval-after-load 'better-jumper
  (advice-add 'helixel-forward-word-start :around
              #'my/better-jump-preserve-pos-advice))

(let ((fold-next (concat "z " (or (bound-and-true-p kaizen/nav-down) "j")))
      (fold-prev (concat "z " (or (bound-and-true-p kaizen/nav-up) "k"))))
  (helixel-define-key 'normal (kbd "z r") #'husky-fold-open)
  (helixel-define-key 'normal (kbd "z R") #'husky-fold-open-all)
  (helixel-define-key 'normal (kbd "z A") #'husky-fold-toggle-all)
  (helixel-define-key 'normal (kbd "z a") #'husky-fold-toggle)
  (helixel-define-key 'normal (kbd fold-next) #'husky-fold-next)
  (helixel-define-key 'normal (kbd "z M") #'husky-fold-close-all)
  (helixel-define-key 'normal (kbd fold-prev) #'husky-fold-previous))

;; Keep startup exactly like in the working version.
(helixel-mode)

;; `helixel-mode' init may re-attach SPC to its own space-map — re-assert the
;; kaizen leader as the last thing so "SPC …" keeps flowing into
;; `mode-specific-map'.
(kaizen/helixel-bind-leader)

(provide 'kaizen-bindings-helixel)
;;; bindings/helixel.el ends here

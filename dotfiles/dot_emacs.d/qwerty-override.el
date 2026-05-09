;;; qwerty-override.el --- QWERTY key overrides for meow and related packages
;;; Loaded automatically when layout != colemak
;;
;; This file overrides colemak-specific keybindings with QWERTY equivalents.
;; It is loaded by the layout detection block at the end of README.org.

(defun my/meow-setup-qwerty ()
  "Override meow keybindings for QWERTY layout."
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)

  ;; Motion state
  (meow-motion-overwrite-define-key
   '("j" . meow-next)
   '("k" . meow-prev)
   '("<escape>" . ignore))

  ;; Leader keys
  (meow-leader-define-key
   '("j" . "H-j")
   '("k" . "H-k")
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

  ;; Normal state — layout-dependent keys only
  (meow-normal-define-key
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
   '("i" . meow-append)
   '("j" . meow-next)
   '("J" . meow-next-expand)
   '("k" . meow-prev)
   '("K" . meow-prev-expand)
   '("l" . meow-right)
   '("L" . meow-right-expand)
   '("n" . meow-search)
   '("e" . meow-next-word)
   '("E" . meow-next-symbol)
   '("I" . my/edit-before-bol)
   '("gk" . beginning-of-line)
   '("gj" . my/meow-select-till-eol)
   '("U" . meow-undo-in-selection)))

;; --- C-n/C-e → C-j/C-k overrides ---

;; Minibuffer history
(define-key minibuffer-local-map (kbd "C-j") 'next-history-element)
(define-key minibuffer-local-map (kbd "C-k") 'previous-history-element)
(define-key read--expression-map (kbd "C-j") 'next-history-element)
(define-key read--expression-map (kbd "C-k") 'previous-history-element)

;; Vertico completion
(with-eval-after-load 'vertico
  (define-key vertico-map (kbd "C-j") 'vertico-next)
  (define-key vertico-map (kbd "C-k") 'vertico-previous)
  (define-key vertico-map (kbd "C-n") 'vertico-next-group)
  (define-key vertico-map (kbd "C-p") 'vertico-previous-group))

;; Smartparens overrides
(with-eval-after-load 'smartparens
  (define-key smartparens-mode-map (kbd "e") nil)
  (define-key smartparens-mode-map (kbd "j") 'sp-down-sexp)
  (define-key smartparens-mode-map (kbd "k") 'sp-up-sexp)
  (define-key smartparens-mode-map (kbd "l") 'sp-forward-sexp)
  (define-key smartparens-mode-map (kbd "n") 'sp-forward-slurp-sexp))

;; Org-agenda overrides
(with-eval-after-load 'org-agenda
  (define-key org-agenda-mode-map "j" 'org-agenda-next-line)
  (define-key org-agenda-mode-map "k" 'org-agenda-previous-line)
  (define-key org-agenda-mode-map "l" 'org-agenda-later)
  (define-key org-agenda-mode-map "L" 'org-agenda-log-mode)
  (define-key org-agenda-mode-map "J" 'org-agenda-next-item)
  (define-key org-agenda-mode-map "K" 'org-agenda-previous-item)
  (define-key org-agenda-mode-map "i" 'org-agenda-clock-in)
  (define-key org-agenda-mode-map "e" 'org-agenda-set-effort))

;; Magit section navigation
(with-eval-after-load 'magit
  (define-key magit-status-mode-map (kbd "C-j") 'magit-section-forward)
  (define-key magit-status-mode-map (kbd "C-k") 'magit-section-backward)
  (define-key magit-log-mode-map (kbd "C-j") 'magit-section-forward)
  (define-key magit-log-mode-map (kbd "C-k") 'magit-section-backward)
  (define-key magit-diff-mode-map (kbd "C-j") 'magit-section-forward)
  (define-key magit-diff-mode-map (kbd "C-k") 'magit-section-backward)
  (define-key magit-file-section-map (kbd "C-j") 'magit-section-forward)
  (define-key magit-hunk-section-map (kbd "C-j") 'magit-section-forward))

;; ECA chat history
(with-eval-after-load 'eca
  (define-key eca-chat-mode-map (kbd "C-j") 'eca-chat--key-pressed-next-prompt-history)
  (define-key eca-chat-mode-map (kbd "C-k") 'eca-chat--key-pressed-previous-prompt-history))

;; Apply meow overrides last (redefines keymaps)
(my/meow-setup-qwerty)

;;; qwerty-override.el ends here

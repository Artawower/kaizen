;;; qwerty-override.el --- QWERTY key overrides for navigation -*- lexical-binding: t; -*-

(define-key minibuffer-local-map (kbd "C-j") 'next-history-element)
(define-key minibuffer-local-map (kbd "C-k") 'previous-history-element)
(define-key read--expression-map (kbd "C-j") 'next-history-element)
(define-key read--expression-map (kbd "C-k") 'previous-history-element)

(with-eval-after-load 'vertico
  (define-key vertico-map (kbd "C-j") 'vertico-next)
  (define-key vertico-map (kbd "C-k") 'vertico-previous)
  (define-key vertico-map (kbd "C-n") 'vertico-next-group)
  (define-key vertico-map (kbd "C-p") 'vertico-previous-group))

(with-eval-after-load 'smartparens
  (define-key smartparens-mode-map (kbd "e") nil)
  (define-key smartparens-mode-map (kbd "j") 'sp-down-sexp)
  (define-key smartparens-mode-map (kbd "k") 'sp-up-sexp)
  (define-key smartparens-mode-map (kbd "l") 'sp-forward-sexp)
  (define-key smartparens-mode-map (kbd "n") 'sp-forward-slurp-sexp))

(with-eval-after-load 'org-agenda
  (define-key org-agenda-mode-map "j" 'org-agenda-next-line)
  (define-key org-agenda-mode-map "k" 'org-agenda-previous-line)
  (define-key org-agenda-mode-map "l" 'org-agenda-later)
  (define-key org-agenda-mode-map "L" 'org-agenda-log-mode)
  (define-key org-agenda-mode-map "J" 'org-agenda-next-item)
  (define-key org-agenda-mode-map "K" 'org-agenda-previous-item)
  (define-key org-agenda-mode-map "i" 'org-agenda-clock-in)
  (define-key org-agenda-mode-map "e" 'org-agenda-set-effort))

(with-eval-after-load 'magit
  (define-key magit-status-mode-map (kbd "C-j") 'magit-section-forward)
  (define-key magit-status-mode-map (kbd "C-k") 'magit-section-backward)
  (define-key magit-log-mode-map (kbd "C-j") 'magit-section-forward)
  (define-key magit-log-mode-map (kbd "C-k") 'magit-section-backward)
  (define-key magit-diff-mode-map (kbd "C-j") 'magit-section-forward)
  (define-key magit-diff-mode-map (kbd "C-k") 'magit-section-backward)
  (define-key magit-file-section-map (kbd "C-j") 'magit-section-forward)
  (define-key magit-hunk-section-map (kbd "C-j") 'magit-section-forward))

(with-eval-after-load 'eca
  (define-key eca-chat-mode-map (kbd "C-j") 'eca-chat--key-pressed-next-prompt-history)
  (define-key eca-chat-mode-map (kbd "C-k") 'eca-chat--key-pressed-previous-prompt-history))

(provide 'qwerty-override)
;;; qwerty-override.el ends here

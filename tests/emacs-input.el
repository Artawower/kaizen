(require 'ert)
(require 'cl-lib)

(defvar kaizen-test-root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))

(let ((packages (expand-file-name "~/.emacs.d/elpaca/builds")))
  (when (file-directory-p packages)
    (dolist (directory (directory-files packages t "^[^.]"))
      (when (file-directory-p directory)
        (add-to-list 'load-path directory)))))

(defun kaizen-test-form (file marker)
  (with-temp-buffer
    (insert-file-contents (expand-file-name file kaizen-test-root))
    (goto-char (point-min))
    (search-forward marker)
    (goto-char (match-beginning 0))
    (read (current-buffer))))

(eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                        "(defun my/delete-backward-word"))

(defun kaizen-test-delete-without-copying (command)
  (let* ((kill-ring (list "clipboard sentinel"))
         (kill-ring-yank-pointer kill-ring)
         (ring kill-ring)
         (pointer kill-ring-yank-pointer)
         (clipboard-called nil)
         (interprogram-cut-function (lambda (&rest _) (setq clipboard-called t))))
    (call-interactively command)
    (should-not clipboard-called)
    (should (eq kill-ring ring))
    (should (equal kill-ring '("clipboard sentinel")))
    (should (eq kill-ring-yank-pointer pointer))))

(ert-deftest word-deletion-supports-prefix-arguments-without-copying ()
  (dolist (case '((2 "first second third" nil "first ")
                  (-1 "first second" t " second")
                  (0 "first second" nil "first second")))
    (with-temp-buffer
      (insert (nth 1 case))
      (when (nth 2 case) (goto-char (point-min)))
      (let ((current-prefix-arg (car case)))
        (kaizen-test-delete-without-copying #'my/delete-backward-word))
      (should (equal (buffer-string) (nth 3 case))))))

(defun kaizen-test-corfu-bindings ()
  (dolist (package '("corfu" "corfu-popupinfo"))
    (let* ((form (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                                   (concat "(use-package " package "\n")))
           (bindings (cadr (memq :bind form)))
           (map (make-sparse-keymap)))
      (while bindings
        (let ((binding (pop bindings)))
          (if (eq binding :map)
              (setq map (symbol-value (pop bindings)))
            (define-key map (if (stringp (car binding))
                                (kbd (car binding))
                              (car binding))
              (cdr binding))))))))

(defun kaizen-test-delete-word-keys ()
  (dolist (key '("C-w" "M-DEL" "M-<backspace>"))
    (erase-buffer)
    (insert "first second")
    (let ((command (key-binding (kbd key))))
      (should (eq command #'my/delete-backward-word))
      (kaizen-test-delete-without-copying command)
      (should (equal (buffer-string) "first ")))))

(ert-deftest terminal-minibuffer-deletes-word-without-a-mark ()
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                          "(define-key minibuffer-local-map (kbd \"C-w\")"))
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) nil)))
    (dolist (map '(minibuffer-local-map minibuffer-local-ns-map
                   minibuffer-local-completion-map minibuffer-local-must-match-map
                   minibuffer-local-filename-completion-map read-expression-map))
      (with-temp-buffer
        (use-local-map
         (if (eq map 'minibuffer-local-filename-completion-map)
             (make-composed-keymap (list (symbol-value map) minibuffer-local-completion-map))
           (symbol-value map)))
        (insert (propertize "Search: " 'read-only t 'field 'minibuffer-prompt
                            'rear-nonsticky t))
        (insert "first second")
        (should-not (mark t))
        (let ((command (key-binding (kbd "C-w"))))
          (should (eq command #'my/delete-backward-word))
          (kaizen-test-delete-without-copying command))
        (should (equal (buffer-string) "Search: first "))))))

(ert-deftest gui-minibuffer-keeps-cut-region-binding ()
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                          "(define-key minibuffer-local-map (kbd \"C-w\")"))
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t)))
    (with-temp-buffer
      (use-local-map minibuffer-local-completion-map)
      (insert "first second")
      (set-mark 7)
      (let* ((copied nil)
             (interprogram-cut-function (lambda (text &rest _) (setq copied text)))
             (kill-ring nil)
             (command (key-binding (kbd "C-w"))))
        (should (eq command #'kill-region))
        (call-interactively command)
        (should (equal copied "second"))
        (should (equal (car kill-ring) "second")))
      (should (equal (buffer-string) "first ")))))

(ert-deftest corfu-return-inserts-instead-of-opening-documentation ()
  (skip-unless (require 'corfu nil t))
  (kaizen-test-corfu-bindings)
  (should (eq (lookup-key corfu-map (kbd "RET")) #'corfu-insert))
  (should (eq (lookup-key corfu-map (kbd "C-m")) #'corfu-insert))
  (should (eq (lookup-key corfu-map (kbd "<return>")) #'corfu-insert))
  (should (eq (lookup-key corfu-map (kbd "M-h")) #'corfu-popupinfo-documentation))
  (dolist (key '("RET" "<return>"))
    (with-temp-buffer
      (buffer-enable-undo)
      (insert "pri")
      (setq-local completion-in-region-mode-predicate (lambda () t))
      (corfu--setup (point-min) (point) '("private") nil)
      (setq corfu--candidates '("private")
            corfu--base ""
            corfu--index 0)
      (call-interactively (lookup-key corfu-map (kbd key)))
      (should (equal (buffer-string) "private"))
      (should-not completion-in-region-mode))))

(ert-deftest corfu-escape-dismisses-completion-without-leaving-insert ()
  (skip-unless (and (require 'corfu nil t) (require 'helixel nil t)))
  (kaizen-test-corfu-bindings)
  (should (eq (lookup-key corfu-map [escape]) #'corfu-quit))
  (with-temp-buffer
    (buffer-enable-undo)
    (insert "env")
    (call-interactively #'helixel-insert)
    (setq-local completion-in-region-mode-predicate (lambda () t))
    (corfu--setup (point-min) (point-max) '("environment" "env") nil)
    (should completion-in-region-mode)
    (should (eq (key-binding [escape]) #'corfu-quit))
    (call-interactively (key-binding [escape]))
    (should-not completion-in-region-mode)
    (should (equal (buffer-string) "env"))
    (should (eq helixel--current-state 'insert))
    (should (eq (key-binding [escape]) #'helixel-insert-exit))))

(ert-deftest helixel-insert-deletes-previous-word ()
  (skip-unless (require 'helixel nil t))
  (let ((normal-binding (lookup-key helixel-normal-map (kbd "C-w"))))
    (eval (kaizen-test-form "dotfiles/dot_emacs.d/bindings/helixel.el"
                            "(dolist (key '(\"C-w\""))
    (should (equal normal-binding (lookup-key helixel-normal-map (kbd "C-w")))))
  (with-temp-buffer
    (helixel-insert-state 1)
    (kaizen-test-delete-word-keys)))

(ert-deftest hel-insert-deletes-previous-word ()
  (skip-unless (require 'hel nil t))
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/bindings/hel.el"
                          "(hel-keymap-global-set :state 'insert"))
  (with-temp-buffer
    (hel-local-mode 1)
    (hel-insert-state)
    (kaizen-test-delete-word-keys)))

(ert-deftest meow-insert-keymap-deletes-previous-word ()
  (let ((insert-map (make-sparse-keymap)))
    (cl-letf (((symbol-function 'meow-insert-define-key)
               (lambda (&rest definitions)
                 (dolist (definition definitions)
                   (define-key insert-map (kbd (car definition)) (cdr definition))))))
      (eval (kaizen-test-form "dotfiles/dot_emacs.d/bindings/meow.el"
                              "(meow-insert-define-key\n")))
    (with-temp-buffer
      (use-local-map insert-map)
      (kaizen-test-delete-word-keys)))
  (let* ((form (kaizen-test-form "dotfiles/dot_emacs.d/bindings/meow.el"
                                "(use-package meow\n"))
         (cursor (assq 'meow-cursor-type-insert (cdr (memq :custom form)))))
    (should (eq (eval (cadr cursor)) 'bar))))

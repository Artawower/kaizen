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
    (let ((case-fold-search nil))
      (search-forward marker))
    (goto-char (match-beginning 0))
    (read (current-buffer))))

(eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                        "(defun my/delete-backward-word"))
(eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                        "(defconst my/delete-backward-word-binding"))

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

(ert-deftest auto-dark-follows-system-appearance-without-a-gui-frame ()
  (skip-unless (and (require 'auto-dark nil t) (require 'use-package nil t)))
  (dolist (initial-window-system '(nil neo ns))
    (let ((system-type 'darwin)
          (window-system initial-window-system)
          (auto-dark-mode nil)
          (auto-dark-mode-hook nil)
          (auto-dark-allow-osascript nil)
          (auto-dark-detection-method nil)
          (auto-dark--last-dark-mode-state 'unknown)
          (auto-dark--timer nil)
          (ns-system-appearance-change-functions nil)
          (after-make-frame-functions nil)
          (appearance 'light)
          applied-themes)
      (cl-letf (((symbol-function 'ns-do-applescript) (lambda (&rest _) "false"))
                ((symbol-function 'auto-dark--is-dark-mode-osascript)
                 (lambda () (eq appearance 'dark)))
                ((symbol-function 'auto-dark--update-frame-backgrounds) #'ignore)
                ((symbol-function 'auto-dark--enable-themes)
                 (lambda (themes) (setq applied-themes themes))))
        (unwind-protect
            (progn
              (eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                                      "(use-package auto-dark"))
              (should (equal applied-themes '(modern-catppuccin-latte)))
              (if (eq initial-window-system 'ns)
                  (progn
                    (should (eq auto-dark-detection-method 'applescript))
                    (should-not auto-dark--timer)
                    (should (memq #'auto-dark--set-theme ns-system-appearance-change-functions)))
                (should (eq auto-dark-detection-method 'osascript))
                (should (memq auto-dark--timer timer-list))
                (setq appearance 'dark)
                (funcall (timer--function auto-dark--timer))
                (should (equal applied-themes '(modern-tokyo)))
                (setq appearance 'light)
                (funcall (timer--function auto-dark--timer))
                (should (equal applied-themes '(modern-catppuccin-latte)))
                (let ((previous-timer auto-dark--timer))
                  (auto-dark-mode 1)
                  (should-not (memq previous-timer timer-list))
                  (should (memq auto-dark--timer timer-list))))
              (auto-dark-mode -1)
              (should-not (memq auto-dark--timer timer-list)))
          (auto-dark-mode -1)
          (auto-dark-stop-timer))))))

(ert-deftest buffer-bindings-work-before-consult-loads ()
  (skip-unless (and (require 'hel nil t) (require 'helixel nil t)))
  (should-not (featurep 'consult))
  (dolist (scheme '((hel . hel-normal-state-map) (helixel . helixel-normal-map)))
    (define-key (symbol-value (cdr scheme)) (kbd "SPC") (make-sparse-keymap))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name (format "dotfiles/dot_emacs.d/bindings/%s.el" (car scheme))
                         kaizen-test-root))
      (goto-char (point-min))
      (search-forward "(autoload 'consult-buffer")
      (goto-char (match-beginning 0))
      (dotimes (_ 4) (eval (read (current-buffer)) t)))
    (dolist (binding '(("SPC b a" . consult-buffer) ("SPC b b" . consult-project-buffer)))
      (should (eq (lookup-key (symbol-value (cdr scheme)) (kbd (car binding)))
                  (cdr binding)))
      (should (commandp (cdr binding)))
      (should (autoloadp (symbol-function (cdr binding))))))
  (should-not (featurep 'consult)))

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

(ert-deftest copying-after-word-deletion-does-not-append-old-kill ()
  (dolist (key '("C-w" "M-DEL" "M-<backspace>"))
    (let* ((kill-ring (list "clipboard sentinel"))
           (kill-ring-yank-pointer kill-ring)
           (copied nil)
           (interprogram-cut-function (lambda (text &rest _) (setq copied text)))
           (this-command nil)
           (last-command nil))
      (save-window-excursion
        (with-temp-buffer
          (switch-to-buffer (current-buffer))
          (use-local-map (make-sparse-keymap))
          (define-key (current-local-map) (kbd key) my/delete-backward-word-binding)
          (insert "first second")
          (set-mark (point-min))
          (execute-kbd-macro (kbd (concat key " M-w")))
          (should (equal (buffer-string) "first "))
          (should (equal copied "first "))
          (should (equal kill-ring '("first " "clipboard sentinel"))))))))

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

(ert-deftest embark-collect-uses-native-consult-preview ()
  (skip-unless (and (require 'use-package nil t)
                    (require 'embark nil t)
                    (require 'consult nil t)))
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                          "(use-package embark-consult"))
  (with-temp-buffer
    (embark-collect-mode)
    (should (derived-mode-p 'embark-collect-mode))
    (should-not (memq 'consult-preview-at-point-mode embark-collect-mode-hook))
    (should (memq #'consult--default-completion-list-preview post-command-hook))
    (should (memq #'embark-consult--collect-candidate
                  consult--completion-candidate-hook))))

(ert-deftest html-lsp-corfu-preserves-member-access-and-surrounding-text ()
  (skip-unless (and (require 'corfu nil t)
                    (require 'cape nil t)
                    (require 'lsp-proxy nil t)))
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                          "(defun my/lsp-proxy-completion-with-dabbrev"))
  (kaizen-test-corfu-bindings)
  (dolist (mode '(html-mode html-ts-mode))
    (dolist (prefix '("" "me"))
      (with-temp-buffer
        (funcall mode)
        (buffer-enable-undo)
        (insert "        {{ deposit." prefix " }}\n      </div>")
        (goto-char (point-min))
        (search-forward "deposit.")
        (let* ((member-start (point))
               (edit-start (eglot--pos-to-lsp-position))
               (edit-end (progn (forward-char (length prefix))
                                (eglot--pos-to-lsp-position)))
               (original-syntax (syntax-table))
               (requested-prefix nil))
          (setq-local buffer-file-name "/tmp/kaizen-completion.html"
                      lsp-proxy-mode t
                      lsp-proxy--buffer-opened t
                      lsp-proxy--has-any-servers t
                      completion-in-region-mode-predicate (lambda () t))
          (lsp-proxy--completion-setup)
          (cl-letf (((symbol-function 'lsp-proxy--ensure-connection) #'ignore)
                    ((symbol-function 'lsp-proxy--send-did-change) #'ignore)
                    ((symbol-function 'lsp-proxy--async-resolve) #'ignore)
                    ((symbol-function 'jsonrpc-request)
                     (lambda (_connection method params &rest _args)
                       (should (eq method 'textDocument/completion))
                       (let ((context (plist-get params :context)))
                         (setq requested-prefix (plist-get context :prefix))
                         (list (list :language_server_name "angular"
                                     :start (+ member-start (length prefix))
                                     :end (+ (plist-get context :boundsStart) 6)
                                     :item (list :label "method"
                                                 :textEdit (list :newText "method"
                                                                 :range (list :start edit-start
                                                                              :end edit-end)))))))))
            (let* ((result (my/lsp-proxy-completion-with-dabbrev
                            #'lsp-proxy-completion-at-point))
                   (completion-extra-properties (nthcdr 3 result)))
              (corfu--setup (car result) (cadr result) (nth 2 result) nil)
              (setq corfu--candidates
                    (all-completions prefix (nth 2 result))
                    corfu--base ""
                    corfu--index 0)
              (call-interactively (lookup-key corfu-map (kbd "RET")))))
          (should (equal (buffer-string)
                         "        {{ deposit.method }}\n      </div>"))
          (should (equal requested-prefix prefix))
          (should (eq (syntax-table) original-syntax))
          (should (eq (char-syntax ?.) ?_))
          (should-not completion-in-region-mode))))))

(ert-deftest vue-lsp-corfu-completes-path-segment-after-slash ()
  (skip-unless (and (require 'corfu nil t)
                    (require 'cape nil t)
                    (require 'lsp-proxy nil t)
                    (require 'vue-ts-mode nil t)
                    (treesit-ready-p 'vue t)))
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                          "(defun my/lsp-proxy-completion-with-dabbrev"))
  (kaizen-test-corfu-bindings)
  (with-temp-buffer
    (vue-ts-mode)
    (buffer-enable-undo)
    (insert "import X from \"@/com\";\n")
    (goto-char (point-min))
    (search-forward "@/")
    (let* ((segment-start (point))
           (edit-start (eglot--pos-to-lsp-position))
           (edit-end (progn (forward-char 3)
                            (eglot--pos-to-lsp-position)))
           (original-syntax (syntax-table)))
      (setq-local buffer-file-name "/tmp/kaizen-completion.vue"
                  lsp-proxy-mode t
                  lsp-proxy--buffer-opened t
                  lsp-proxy--has-any-servers t
                  completion-in-region-mode-predicate (lambda () t))
      (lsp-proxy--completion-setup)
      (cl-letf (((symbol-function 'lsp-proxy--ensure-connection) #'ignore)
                ((symbol-function 'lsp-proxy--send-did-change) #'ignore)
                ((symbol-function 'lsp-proxy--async-resolve) #'ignore)
                ((symbol-function 'jsonrpc-request)
                 (lambda (_connection method params &rest _args)
                   (should (eq method 'textDocument/completion))
                   (let ((context (plist-get params :context)))
                     (list (list :language_server_name "vue-language-server"
                                 :start (+ segment-start 3)
                                 :end (+ (plist-get context :boundsStart) 10)
                                 :item (list :label "components"
                                             :textEdit (list :newText "components"
                                                             :range (list :start edit-start
                                                                          :end edit-end)))))))))
        (let* ((result (my/lsp-proxy-completion-with-dabbrev
                        #'lsp-proxy-completion-at-point))
               (completion-extra-properties (nthcdr 3 result)))
          (corfu--setup (car result) (cadr result) (nth 2 result) nil)
          (setq corfu--candidates
                (all-completions "com" (nth 2 result))
                corfu--base ""
                corfu--index 0)
          (call-interactively (lookup-key corfu-map (kbd "RET")))))
      (should (equal (buffer-string) "import X from \"@/components\";\n"))
      (should (eq (syntax-table) original-syntax))
      (should (eq (char-syntax ?/) ?_))
      (should-not completion-in-region-mode))))

(ert-deftest html-lsp-bounds-do-not-change-other-modes-or-dabbrev-syntax ()
  (skip-unless (require 'cape nil t))
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org"
                          "(defun my/lsp-proxy-completion-with-dabbrev"))
  (dolist (mode '(html-mode html-ts-mode emacs-lisp-mode typescript-ts-mode))
    (with-temp-buffer
      (funcall mode)
      (let ((original-syntax (syntax-table))
            (original-dot (char-syntax ?.))
            (html (derived-mode-p 'html-mode 'html-ts-mode)))
        (cl-letf (((symbol-function 'cape-dabbrev)
                   (lambda ()
                     (should (eq (syntax-table) original-syntax))
                     (should (eq (char-syntax ?.) original-dot))
                     'dabbrev)))
          (should (eq (my/lsp-proxy-completion-with-dabbrev
                       (lambda ()
                         (should (eq (char-syntax ?.)
                                     (if html ?. original-dot)))
                         nil))
                      'dabbrev)))
        (should (eq (syntax-table) original-syntax))))))

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

(defun kaizen-test-helixel-search-bindings ()
  (dolist (name '(kaizen/helixel-search-or-next kaizen/helixel-search-reverse))
    (eval (kaizen-test-form "dotfiles/dot_emacs.d/bindings/helixel.el"
                            (format "(defun %s " name))))
  (dolist (key '("n" "N"))
    (eval (kaizen-test-form "dotfiles/dot_emacs.d/bindings/helixel.el"
                            (format "(helixel-define-key 'normal \"%s\"" key)))))

(ert-deftest helixel-search-repeat-keeps-base-direction ()
  (skip-unless (require 'helixel nil t))
  (kaizen-test-helixel-search-bindings)
  (dolist (case '(("/" forward 1 (5 1 5 9 5 1 9 1 5 1 13 1))
                  ("?" backward 16 (9 13 9 5 9 13 5 13 9 13 1 13))))
    (save-window-excursion
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (insert "foo foo foo foo")
        (goto-char (nth 2 case))
        (helixel-normal-state 1)
        (execute-kbd-macro (kbd (concat (car case) " f o o RET")))
        (dolist (step (cl-mapcar #'cons
                                '("n" "N" "n" "n" "N" "N" "2 n" "2 N" "n" "N" "N" "n")
                                (nth 3 case)))
          (ert-info ((format "%s search, key %s" (car case) (car step)))
            (execute-kbd-macro (kbd (car step)))
            (should (= (region-beginning) (cdr step)))
            (should (eq (helixel-search--current-dir) (nth 1 case)))
            (should (equal (helixel-search--safe-pattern) "foo"))))))))

(ert-deftest helixel-search-repeat-preserves-regexp ()
  (skip-unless (require 'helixel nil t))
  (kaizen-test-helixel-search-bindings)
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert "foo fxo fyo fzo")
      (goto-char (point-min))
      (helixel-normal-state 1)
      (execute-kbd-macro (kbd "/ f . o RET n N n"))
      (should (= (region-beginning) 5))
      (should (equal (helixel-search--safe-pattern) "f.o"))
      (should (helixel--last-motion-regexp helixel--active-search)))))

(ert-deftest helixel-search-without-active-search-uses-selection-or-word ()
  (skip-unless (require 'helixel nil t))
  (kaizen-test-helixel-search-bindings)
  (dolist (selection '(nil t))
    (save-window-excursion
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (insert "foo foo foo")
        (goto-char (point-min))
        (helixel-normal-state 1)
        (when selection
          (push-mark 4 t t)
          (setq transient-mark-mode t))
        (execute-kbd-macro (kbd "n n"))
        (should (= (region-beginning) 9))
        (should (eq (helixel-search--current-dir) 'forward))))))

(ert-deftest helixel-search-russian-aliases-preserve-command-and-insert-input ()
  (skip-unless (and (require 'helixel nil t) (require 'reverse-im nil t)))
  (require 'quail)
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org" "(quail-define-package\n \"cyrillic-colemak\""))
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org" "(quail-define-rules"))
  (kaizen-test-helixel-search-bindings)
  (let ((function-key-map (copy-keymap function-key-map))
        (local-function-key-map (make-sparse-keymap))
        (reverse-im-cache-file nil)
        (reverse-im--keymaps-alist nil))
    (set-keymap-parent local-function-key-map function-key-map)
    (reverse-im-activate "cyrillic-colemak")
    (save-window-excursion
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (insert "foo foo foo")
        (goto-char (point-min))
        (helixel-normal-state 1)
        (execute-kbd-macro (kbd "/ f o o RET о О о"))
        (should (= (region-beginning) 5))
        (should (eq (helixel-search--current-dir) 'forward))
        (execute-kbd-macro (kbd "i о О <escape>"))
        (should (string-match-p "оО" (buffer-string)))))))

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

(defun kaizen-test-meow-insert-map ()
  (let ((insert-map (make-sparse-keymap)))
    (cl-letf (((symbol-function 'meow-insert-define-key)
               (lambda (&rest definitions)
                 (dolist (definition definitions)
                   (define-key insert-map (kbd (car definition)) (cdr definition))))))
      (eval (kaizen-test-form "dotfiles/dot_emacs.d/bindings/meow.el"
                              "(meow-insert-define-key\n")))
    insert-map))

(ert-deftest meow-insert-keymap-deletes-previous-word ()
  (with-temp-buffer
    (use-local-map (kaizen-test-meow-insert-map))
    (kaizen-test-delete-word-keys))
  (let* ((form (kaizen-test-form "dotfiles/dot_emacs.d/bindings/meow.el"
                                "(use-package meow\n"))
         (cursor (assq 'meow-cursor-type-insert (cdr (memq :custom form)))))
    (should (eq (eval (cadr cursor)) 'bar))))

(defun kaizen-test-ghostel-word-keys ()
  (dolist (key '("C-w" "M-DEL" "M-<backspace>"))
    (ert-info ((format "native Ghostel binding: %s" key))
      (should (eq (key-binding (kbd key)) #'ghostel--send-event)))))

(ert-deftest helixel-insert-keeps-native-ghostel-word-keys ()
  (skip-unless (and (require 'ghostel nil t) (require 'helixel nil t)))
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/bindings/helixel.el"
                          "(dolist (key '(\"C-w\""))
  (let ((was-enabled (bound-and-true-p helixel-global-mode)))
    (unwind-protect
        (progn
          (unless was-enabled (helixel-mode))
          (with-temp-buffer
            (ghostel-mode)
            (helixel-insert)
            (kaizen-test-ghostel-word-keys)))
      (unless was-enabled
        (when (bound-and-true-p helixel-global-mode) (helixel-mode))))))

(ert-deftest hel-insert-keeps-native-ghostel-word-keys ()
  (skip-unless (and (require 'ghostel nil t) (require 'hel nil t)))
  (eval (kaizen-test-form "dotfiles/dot_emacs.d/bindings/hel.el"
                          "(hel-keymap-global-set :state 'insert"))
  (with-temp-buffer
    (ghostel-mode)
    (hel-local-mode 1)
    (hel-insert-state)
    (kaizen-test-ghostel-word-keys)))

(ert-deftest meow-insert-keymap-keeps-native-ghostel-word-keys ()
  (skip-unless (require 'ghostel nil t))
  (with-temp-buffer
    (ghostel-mode)
    (let ((minor-mode-map-alist
           (cons (cons t (kaizen-test-meow-insert-map)) minor-mode-map-alist)))
      (kaizen-test-ghostel-word-keys))))

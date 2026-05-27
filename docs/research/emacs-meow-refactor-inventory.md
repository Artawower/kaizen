# Emacs meow refactor inventory

## 1. Functions that move целиком

These defuns contain `meow-*-define-key`, `meow-define-keys`, or `meow-*-state-keymap`.

- `meow-setup` — `1135-1267`
  - contains `meow-motion-overwrite-define-key`, `meow-leader-define-key`, `meow-normal-define-key`, `meow-define-keys` for `motion`/`insert`/`normal`
- `my/meow-setup-custom-modes` — `1306-1331`
  - contains `meow-define-state` and `meow-define-keys 'paren`
- `my/meow-setup-agenda-mode` — `1336-1375`
  - contains `meow-agenda-motion-keymap` and `meow-define-keys 'agenda-motion`
- `my/meow-yank-below` — `1069-1073`
- `my/meow-change-till-eol` — `1077-1082`
- `my/meow-select-till-eol` — `1086-1090`
- `my/meow-backward-till` — `1094-1097`

## 2. `use-package meow`

- `use-package meow` — `1402-1416`
  - `:custom` → `(meow-use-clipboard t)`
  - `:config` → `(meow-setup)`, `define-key mode-specific-map` cleanup for `j`/`e`, `(my/meow-thing-register)`, `(my/meow-setup-custom-modes)`, `(my/meow-setup-state-per-modes)`, `advice-add` for `meow-change`, `(meow-global-mode 1)`
  - no `:hook`
  - no `:bind`

## 3. Package bindings with `:map meow-*`

### `zoom-window` — `708-711`

- `:map meow-normal-state-keymap`
  - `("\\ m" . zoom-window-zoom)`
- `:map meow-motion-state-keymap`
  - `("\\ m" . zoom-window-zoom)`

### `avy` — `1568-1570`

- `:map meow-normal-state-keymap`
  - `("f" . my/avy-select-word)`
  - `("\\f" . avy-goto-char-timer)`

### `bm` — `1657-1659`

- `:map meow-normal-state-keymap`
  - `("]m" . bm-next)`
  - `("[m" . bm-previous)`

### `undo-fu` — `1786-1788`

- `:map meow-normal-state-keymap`
  - `("U" . undo-fu-only-redo)`
  - `("u" . undo-fu-only-undo)`

### `persistent-kmacro` — `1878-1879`

- `:map meow-normal-state-keymap`
  - `("#" . persistent-kmacro-apply)`

### `apheleia` — `2052-2053`

- `:map meow-normal-state-keymap`
  - `("\\p" . apheleia-format-buffer)`

### `dirvish` — `2124-2125`

- `:map meow-normal-state-keymap`
  - `("gf" . dirvish-quick-access)`

### `git-gutter` — `2414-2416`

- `:map meow-normal-state-keymap`
  - `("]g" . git-gutter:next-hunk)`
  - `("[g" . git-gutter:previous-hunk)`

### `smerge-mode` — `2697-2699`

- `:map meow-normal-state-keymap`
  - `("g s" . smerge-next)`
  - `("g S" . smerge-prev)`

### `eglot` — `3272-3276`

- `:map meow-normal-state-keymap`
  - `("g i" . eglot-find-implementation)`
  - `("g r" . xref-find-references)`
  - `("\\i" . my/eglot-toggle-inlay-hints)`
  - `("\\l" . eglot-code-actions)`

### `flymake` — `3416-3418`

- `:map meow-normal-state-keymap`
  - `("]d" . flymake-goto-next-error)`
  - `("[d" . flymake-goto-prev-error)`

### `eldoc-box` — `3525-3527`

- `:map meow-normal-state-keymap`
  - `("\\b" . my/toggle-eldoc-buffer)`
  - `("\\h" . eldoc-box-help-at-point)`

### `pretty-ts-errors` — `3849-3850`

- `:map meow-normal-state-keymap`
  - `("\\e" . pretty-ts-errors-show-error-at-point)`

### `org` — `4453-4455`

- `:map meow-normal-state-keymap`
  - `("\\o" . org-mode)`
  - `("\\a" . org-agenda)`

### `google-translate` — `4945-4946`

- `:map meow-normal-state-keymap`
  - `("\\ t" . google-translate-smooth-translate)`

### `husky` — `5191-5205`

- `:map meow-normal-state-keymap`
  - `("gd" . husky-lsp-find-definition)`
  - `("%" . husky-navigation-bounce-paren)`
  - `("g F" . husky-lsp-avy-go-to-definition)`
  - `("g f" . husky-lsp-avy-go-to-definition)`
  - `("g D" . husky-buffers-side-husky-actions-find-definition)`
  - `("z r" . husky-fold-open)`
  - `("z R" . husky-fold-open-all)`
  - `("s-y" . husky-lsp-copy-to-register-1)`
  - `("s-p" . husky-lsp-paste-from-register-1)`
  - `("z A" . husky-fold-toggle-all)`
  - `("z a" . husky-fold-toggle)`
  - `("z j" . husky-fold-next)`
  - `("z M" . husky-fold-close-all)`
  - `("z k" . husky-fold-previous)`

## 4. `with-eval-after-load 'meow`

- `with-eval-after-load 'meow` — `2608-2645`
  - `defvar my/meow-ediff-state-keymap`
  - parent keymap: `meow-motion-state-keymap`
  - `meow-define-state ediff`
  - `defun my/ediff-enable-meow-state`
  - `defun my/ediff-disable-meow-state`
  - `defvar-local my/ediff-meow-was-enabled`
  - `defvar-local my/ediff-meow-previous-state`

## 5. Hooks and variables tied to meow

### `setq` / `setq-local`

- `meow-setup` — `1136-1138`
  - `meow--kbd-forward-line`, `meow--kbd-backward-line`, `meow-cheatsheet-layout`
- `my/meow-setup-custom-modes` — `1307`, `1315`
  - `meow-paren-keymap`, `meow-cursor-type-paren`
- `my/meow-setup-agenda-mode` — `1337`
  - `meow-agenda-motion-keymap`
- `with-eval-after-load 'meow` — `2628`, `2632`
  - `setq-local my/ediff-meow-was-enabled`
  - `setq-local my/ediff-meow-previous-state`

### `meow-mode-state-list` registrations

- `my/meow-setup-agenda-mode` — `1375`
  - `(org-agenda-mode . agenda-motion)`
- `my/meow-setup-state-per-modes` — `1381-1397`
  - `elpaca-info-mode`, `flymake-diagnostics-buffer-mode`, `flycheck-error-list-mode`, `magit-process-mode`, `compilation-mode`, `helpful-mode`, `help-mode`, `detached-compilation-mode-map`, `messages-buffer-mode`, `debug-mode`, `debugger-mode`, `ediff-mode`, `ediff-meta-mode`, `grep-mode`

### explicit hooks / hook-like usages

- `2486-2487` — `blamer`
  - `(meow-insert-mode . my/disable-blamer-mode)`
  - `(meow-normal-mode . blamer-mode)`
- `2660-2663` — ediff integration
  - `remove-hook 'ediff-mode-hook #'meow-motion-mode`
  - `remove-hook 'ediff-meta-mode-hook #'meow-motion-mode`
  - `add-hook 'ediff-meta-mode-hook #'my/ediff-enable-meow-state`
  - `add-hook 'ediff-startup-hook ...`
- `3153` — `(add-hook 'meow-insert-exit-hook (lambda () (corfu-quit)))`
- `3421` — `(flymake-diagnostics-buffer-mode . meow-normal-mode)`
- `3445-3446` — `(meow-normal-mode . my/toggle-flymake-posframe)`, `(meow-insert-mode . my/toggle-flymake-posframe)`
- `4262-4267` — `add-hook 'meow-insert-enter-hook`, `add-hook 'meow-insert-exit-hook`

## Additional meow touchpoints outside the requested buckets

- `my/meow-thing-register` — `1273-1301`
- `my/meow--keypad-format-key-1` — `1508-1515`
- `advice-add 'meow--keypad-format-key-1 :override` — `1558`
- `use-package meow-tree-sitter` — `1421-1425`
- `global-set-key (kbd "s-c") 'meow-save` — `1442`
- `meow-normal-mode` predicate check — `4271`

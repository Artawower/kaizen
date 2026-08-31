(require "helix/configuration.scm")

(line-number 'relative)
(set-option! 'gutters (list 'diagnostics 'spacer 'line-numbers 'diff))
(mouse #t)
(middle-click-paste #t)
(scroll_lines 3)
(shell (list "/usr/bin/env" "xonsh" "-c"))
(text-width 80)
(set-option! 'workspace-lsp-roots
  (list ".git"
    ".hg"
    "Cargo.toml"
    "package.json"
    "go.mod"
    "angular.json"
    "nx.json"
    "pnpm-workspace.yaml"))
(preview-completion-insert #t)
(completion-trigger-len 2)
(auto-completion #t)
(auto-format #t)
(set-option! 'auto-save #f)
(idle-timeout 400)
(completion-timeout 250)
(set-option! 'clipboard-provider "termcode")
(indent-guides (ig-render #f) (ig-character #\╎) (ig-skip-levels 1))
(statusline
  #:left
  (list 'mode
    'spinner
    'version-control
    'spacer
    'separator
    'file-base-name
    'read-only-indicator
    'file-modification-indicator)
  #:center
  '()
  #:right
  (list 'diagnostics
    'workspace-diagnostics
    'position
    'total-line-numbers
    'position-percentage
    'file-encoding
    'file-line-ending
    'file-type
    'register
    'selections)
  #:separator
  "│")
(lsp
  (hash 'enable #t
    'display-messages
    #t
    'auto-signature-help
    #t
    'display-inlay-hints
    #t
    'display-signature-help-docs
    #t
    'snippets
    #t
    'goto-reference-include-declaration
    #t))
(cursor-shape #:insert 'bar #:normal 'block #:select 'underline)
(file-picker
  (fp-hidden #f)
  (fp-follow-symlinks #t)
  (fp-deduplicate-links #t)
  (fp-parents #t)
  (fp-ignore #t)
  (fp-git-ignore #t)
  (fp-git-global #t)
  (fp-git-exclude #t))
(auto-pairs
  (hash #\( #\)
    #\{
    #\}
    #\[
    #\]
    #\"
    #\"
    #\`
    #\`
    #\<
    #\>))
(search #:smart-case #t #:wrap-around #t)
(whitespace
  (ws-visible #f)
  (ws-chars
    (hash 'space #\·
      'nbsp
      #\⍽
      'tab
      #\→
      'newline
      #\⏎)))
(soft-wrap (sw-enable #t))

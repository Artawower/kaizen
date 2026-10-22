# Flow keyboard configuration

Flow selects `keys/kaizen.json`, inheriting the local `keys/helix.json`.
Bindings use logical characters: `h/j/k/l` move left/down/up/right and `i`
enters insert mode, including when the Latin layout is Colemak.

The editor leader is Space. Shared sequences include `Space b b` for buffers,
`Space f f` for files, `Space p p` for projects, `Space r t` for tasks, and
`Space w q` to close the current split. Language commands use `Space l d/f/h/r/s`
for diagnostics, formatting, hover, rename, and symbols respectively.
`Space [` and `Space ]`, or `Super+Shift+h/l`, switch tabs.

`0` and `$` move to the beginning and end of the line; selection mode extends
the selection instead. `0` is not a count digit in this profile, so counts
containing zero are unavailable. Counts using digits 1–9 retain Helix behavior.

Explicit Russian aliases for repository-defined command bindings follow
`[keyboard.aliases.ru]` in `config.example.toml`. They preserve command sequences,
modifiers, and case. For example, `р/н/т/г` navigate and `д` enters insert mode;
`Space г ы` renames a symbol. Insert, replacement, search, and character-target
input remain literal: aliases do not transliterate text. Unmanaged built-in
shortcuts are not exhaustively aliased. Modified keys also depend on what the
terminal delivers; control characters such as Ctrl+I/Tab cannot be distinguished
by a legacy terminal protocol.

## Flow 0.7.2 limitations

The bundled Helix profile declares commands that this version does not implement,
including `code_action`, `goto_left_split`, `goto_right_split`, and split swaps.
The Kaizen profile does not add a nonfunctional `Space l a` binding or advertise
directional split navigation. Its obsolete directional split overrides have been
removed. Bundled placeholder bindings in the base Helix profile are otherwise
unchanged; Russian aliases do not make unsupported commands functional.
Folds, bookmarks, split rotation, and distinct horizontal/vertical split creation
are not adapted by this change.

Apply only Flow's configuration with:

```sh
chezmoi apply --source "$PWD/dotfiles" "$HOME/.config/flow"
```

Restart Flow after applying. Check the managed bindings with
`bash tests/flow-config.sh`; this test also runs through `just test`.

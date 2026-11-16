const RECORDING_FONT_SIZE = 26
const GHOSTTY_CONFIG = "~/.config/ghostty/config"
const CAVA_PANEL = r#'kitty +kitten panel \
  --edge=bottom \
  --layer=bottom \
  --lines=760px \
  --margin-bottom=64px \
  --focus-policy=not-allowed \
  --override background_opacity=0 \
  --override window_padding_width=0 \
  /opt/homebrew/bin/cava'#

export def cavabg [] {
    bash -c $CAVA_PANEL
}

def ghostty-font-size [] {
    open --raw ($GHOSTTY_CONFIG | path expand)
    | lines
    | parse --regex '^font-size\s*=\s*(?<size>\S+)'
    | get -o 0.size
}

def set-ghostty-font-size [size] {
    let config = ($GHOSTTY_CONFIG | path expand)
    open --raw $config
    | str replace --regex --multiline '^font-size\s*=.*$' $"font-size = ($size)"
    | save --force $config
    ^pkill -USR2 -x ghostty
}

def emacs-font-height [] {
    let result = (do { ^emacsclient --eval "my/font-height" } | complete)
    if $result.exit_code == 0 { $result.stdout | str trim } else { null }
}

def set-emacs-font-height [height] {
    ^emacsclient --eval $"\(progn \(setq my/font-height ($height)\) \(dolist \(frame \(frame-list\)\) \(my/setup-fonts-to-frame frame\)\)\)" | ignore
}

def start-cava-panel [] {
    ^bash -c $"nohup ($CAVA_PANEL) >/dev/null 2>&1 & echo $!" | str trim
}

export def main [] {
    let state_file = ($env.TMPDIR | path join "rift-recording-state")
    let recording = ($state_file | path exists)

    if not $recording {
        rift-cli execute config set-outer-gaps 60 10 60 10
        if $env.LAST_EXIT_CODE != 0 { return }

        rift-cli execute load-layout ~/.config/rift/layouts/recording.ron
        if $env.LAST_EXIT_CODE != 0 { return }

        let state = {
            ghostty_font_size: (ghostty-font-size)
            emacs_font_height: (emacs-font-height)
            cava_pid: (start-cava-panel)
        }
        $state | to nuon | save --force $state_file

        if $state.ghostty_font_size != null { set-ghostty-font-size $RECORDING_FONT_SIZE }
        if $state.emacs_font_height != null { set-emacs-font-height $RECORDING_FONT_SIZE }
    } else {
        rift-cli execute config set-outer-gaps 14 24 24 24
        if $env.LAST_EXIT_CODE != 0 { return }

        let state = (open --raw $state_file | from nuon | default {})

        if ($state.ghostty_font_size? | is-not-empty) { set-ghostty-font-size $state.ghostty_font_size }
        if ($state.emacs_font_height? | is-not-empty) { set-emacs-font-height $state.emacs_font_height }
        if ($state.cava_pid? | is-not-empty) { do -i { ^kill $state.cava_pid } }

        rm $state_file
    }
}

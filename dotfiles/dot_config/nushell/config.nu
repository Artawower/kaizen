use scripts/project.nu * 

$env.config = ($env.config | merge {
    edit_mode: helix
    buffer_editor: ["emacsclient", "-nw"]
    history: {file_format: sqlite}
    completions: {algorithm: fuzzy, sort: smart, case_sensitive: false}
    render_right_prompt_on_last_line: true
})

source $"($nu.cache-dir)/carapace.nu"
source ~/.atuin/init.nu
source ~/.config/nushell/aliases.nu
source ~/.config/nushell/task-runner.nu
alias vl = jjui
alias pp = kaizen-zoxide-pick


# Disable banner
$env.config.show_banner = false

def "parse mise vars" [] {
    $in | from csv --noheaders --no-infer | rename op name value
}

def --env "apply mise vars" [] {
    for variable in $in {
        if $variable.op == "set" {
            if ($variable.name | str lowercase) == "path" {
                $env.PATH = ($variable.value | split row (char esep))
            } else {
                load-env {($variable.name): $variable.value}
            }
        } else if $variable.op == "hide" {
            try { hide-env $variable.name }
        }
    }
}

def --env "mise hook" [] {
    ^mise hook-env -s nu | parse mise vars | apply mise vars
}

def --env add-nu-hook [field: cell-path hook: any] {
    let field = ($field | split cell-path | update optional true | into cell-path)
    let hooks = ($env.config? | default {} | get $field | default [])
    $env.config = ($env.config? | default {} | upsert $field ($hooks ++ [$hook]))
}

$env.MISE_SHELL = "nu"
add-nu-hook hooks.env_change.PWD {condition: {"MISE_SHELL" in $env}, code: {mise hook}}
$env.config.hooks.pre_prompt = (($env.config.hooks.pre_prompt? | default []) ++ [{||
    if (which mise | is-not-empty) { mise hook }
    if (which zoxide | is-not-empty) {
        let cwd = $env.PWD | path expand
        if (($cwd | path join ".git" | path exists) or ($cwd | path join ".jj" | path exists)) {
            zoxide add -- $cwd
        }
    }
    if (which direnv | is-not-empty) {
        direnv export json | from json | default {} | load-env
    }
}])

if (which starship | is-not-empty) {
    $env.PROMPT_COMMAND = {|| starship prompt --cmd-duration $env.CMD_DURATION_MS --status $env.LAST_EXIT_CODE}
    $env.PROMPT_COMMAND_RIGHT = {|| starship prompt --right}
    $env.PROMPT_INDICATOR = ""
    $env.PROMPT_INDICATOR_VI_INSERT = ""
    $env.PROMPT_INDICATOR_VI_NORMAL = ""
}

let tty = (^tty | complete)
if $tty.exit_code == 0 {
    $env.GPG_TTY = ($tty.stdout | str trim)
}

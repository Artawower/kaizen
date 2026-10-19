alias c = clear
alias с = clear
alias .. = cd ..
alias b = cd -

alias h = hx
alias p = pi
alias o = opencode
alias e = emacsclient -a "" -c -n
alias em = emacs-terminal

alias g = gitu
alias п = gitu
alias ju = jjui
alias jb = python3 ~/.config/scripts/jj-bisect.py
alias ch = chezmoi

def czcd [] { cd (chezmoi source-path) }
alias kdiff = tuicr

alias y = yazi
alias l = python ~/.config/scripts/layout-presets.py

alias pip = pip3
alias python = python3
alias kls = eza --icons=auto
def tree [...args] { eza ...$args --tree }

alias br = bun run
alias bi = bun install
alias bis = bun install --exact --save
alias bid = bun install --exact --save --dev

alias m = minikube
alias ms = minikube start --driver=docker --alsologtostderr
alias md = minikube dashboard
alias kg = kubectl get

alias dc = docker compose
alias dcu = docker compose up
alias d = docker
alias sudo = sudo env PATH=$env.PATH
alias j = just ~/.config/

if (sys host | get name) == "Darwin" {
    def yabai-apps [] { yabai -m query --windows | from json | get app }
    def yabai-titles [] { yabai -m query --windows | from json | get title }
    def displays [] {
        let host = (sys host | get hostname)
        let fqdn = if ($host | str contains ".") { $host } else { $"($host).local" }
        ^bash ($env.HOME | path join ".config/yabai/layouts" $fqdn "desktop.sh")
    }
    alias preserve-displays = bash ~/.config/yabai/restore-script.sh
    alias bu = brew update
}

if (sys host | get name) == "Linux" {
    def limit [...command: string] {
        systemd-run --user --scope -p "MemoryMax=4G" -p "CPUWeight=20" -p "ManagedOOMMemoryPressure=kill" -p "ManagedOOMMemoryPressureLimit=4%" ...$command
    }
}

def hx [...args: string] {
    let dark = if (sys host | get name) == "Darwin" {
        (osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode' | str trim) == "true"
    } else {
        ((gsettings get org.gnome.desktop.interface color-scheme | str lowercase) | str contains "dark")
    }
    let theme = if $dark { "my" } else { "my_light" }
    let config = ($env.HOME | path join ".config/helix/config.toml")
    if ($config | path exists) {
        let content = (open --raw $config | lines | each { |line|
            if ($line | str starts-with "theme = ") { $"theme = \"($theme)\"" } else { $line }
        } | str join (char nl))
        $content | save -f $config
    }
    ^hx ...$args
}

def vis [package: string] { mise use --global $"npm:($package)" }
def docker-clean [] { docker image prune -a; docker system prune -a --volumes }
def clean-space [] { docker-clean; nix-collect-garbage }
def ghll [...args: string] { gh run list --limit 1 --json databaseId --jq '.[0].databaseId' | str trim | do {|id| gh run view $id --log | ^cat ...$args } }
def pnpm-update-all [] {
    let packages = (pnpm list -g --depth=0 --parseable | lines
        | each { |line| $line | path basename }
        | where {|name| $name not-in ["pnpm", "npm"] and not ($name starts-with ".") })
    if ($packages | is-empty) { print "No global packages to update" } else { pnpm add -g ...$packages }
}
def f [pattern: string] { $in | lines | where {|line| $line | str contains --ignore-case $pattern } }
def --env kaizen-zoxide-pick [...args: string] {
    if (which zoxide | is-empty) { return }
    let result = (^zoxide query -i -- ...$args | complete)
    if $result.exit_code == 0 {
        let destination = ($result.stdout | str trim)
        if ($destination | is-not-empty) { cd $destination }
    }
}

def --env dotenv [file: string = ".env"] {
    let path = ($env.PWD | path join $file)
    if not ($path | path exists) { error make {msg: $"No such dotenv file: ($path)"} }
    let values = (open $path | lines | each {|line|
        let line = ($line | str trim)
        if ($line == "" or ($line | str starts-with "#")) { null } else {
            let pair = ($line | str replace -r '^export\s+' '' | split row "=" --number 2)
            if ($pair | length) < 2 { null } else {
                let key = ($pair | first | str trim)
                let value = ($pair | last | str trim | str trim -c '"' | str trim -c "'")
                if ($key =~ '^[A-Za-z_][A-Za-z0-9_]*$') { {($key): $value} } else { null }
            }
        }
    } | compact | reduce -f {} {|item, acc| $acc | merge $item })
    load-env $values
}

def reload [] { exec nu --config ($nu.config-path) --env-config ($nu.env-path) }
alias r = reload

alias c = clear
alias с = clear
alias .. = cd ..
alias b = cd -

alias h = /usr/bin/hx
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
alias z = zellij
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

    let raw_host = (sys host | get hostname)
    let fqdn = if ($raw_host | str contains ".") { $raw_host } else { $"($raw_host).local" }

    def displays [] {
        let fqdn = if ((sys host | get hostname) | str contains ".") { (sys host | get hostname) } else { $"((sys host | get hostname)).local" }
        nu $"($nu.home-path)/.config/yabai/layouts/($fqdn)/desktop.sh"
    }
    alias preserve-displays = nu $"($nu.home-path)/.config/yabai/restore-script.sh"
}

let ssh_config = ($nu.home-path | path join ".ssh" "config")
if ($ssh_config | path exists) {
    let hosts = (
        open $ssh_config
        | lines
        | where { |line| ($line | str downcase | str starts-with "host ") }
        | each { |line| $line | str substring 5.. | split row " " }
        | flatten
        | str trim
        | where { |h|
            not ($h | str contains "*")
            and not ($h | str contains "?")
            and not ($h | str contains "!")
            and not ($h | str replace -a "." "" | str trim | str starts-with "^[0-9]+$")
            and not ($h in ["github.com", "gitlab.com", "bitbucket.org", ""])
        }
        | uniq
    )

    for host in $hosts {
        $env.config = ($env.config | upsert aliases { default $"ssh ($host)" $host })
    }
}

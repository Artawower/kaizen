kaizen_dir := justfile_directory()

default:
    just --choose

# Transfer dotfiles to a new machine
apply:
    chezmoi apply

# Install packages and apply dotfiles
sync:
    python3 kaizen.py sync

# Upgrade all packages and runtime tools
update:
    python3 kaizen.py update

# Interactively bump mise tool versions and capture lock files
bump:
    python3 kaizen.py bump

# Pull deployed dotfile changes back into the source tree
capture:
    python3 kaizen.py capture

# Show environment status
status:
    python3 kaizen.py status

# Bootstrap a fresh machine
install:
    bash install.sh
    just sync

# Dev: symlink repo as chezmoi source instead of copying
dev-link:
    ln -sf "{{kaizen_dir}}/dotfiles" ~/.local/share/chezmoi

kaizen_dir := justfile_directory()

default:
    just --choose

test:
    bash tests/install.sh
    bash tests/dependencies.sh
    bash tests/skills.sh
    bash tests/ai-config.sh
    bash tests/terminal-post-install.sh
    bash tests/helix-steel-post-install.sh
    bash tests/flow-config.sh
    bash tests/mangowm-post-install.sh
    bash tests/noctalia-config.sh
    bash tests/audacity-config.sh
    bash tests/devcache.sh
    bash tests/post-install.sh
    bash tests/chezmoi-ignore.sh

# Transfer dotfiles to a new machine
apply:
    chezmoi apply --source "{{kaizen_dir}}/dotfiles"

# Install packages and apply dotfiles
sync *args:
    python3 kaizen.py sync {{args}}

# Upgrade declared packages and runtime tools
update *args:
    python3 kaizen.py update {{args}}

# Interactively bump tool versions in feature manifests
bump *args:
    python3 kaizen.py bump {{args}}

# Pull deployed dotfile changes back into the source tree
capture:
    python3 kaizen.py capture

# Clean system and toolchain caches
cleanup:
    python3 kaizen.py cleanup

# Show environment status
status *args:
    python3 kaizen.py status {{args}}

# Bootstrap from the current checkout and run a full sync
install:
    KAIZEN_SOURCE_DIR="{{kaizen_dir}}" bash install.sh
    ~/.local/bin/kaizen sync

# Dev: symlink repo as chezmoi source instead of copying
dev-link:
    ln -sfn "{{kaizen_dir}}/dotfiles" ~/.local/share/chezmoi

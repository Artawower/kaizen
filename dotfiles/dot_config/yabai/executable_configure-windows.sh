#!/usr/bin/env bash
touch /tmp/yabai-script-started
sleep 2
touch /tmp/yabai-script-after-sleep
python3 "$HOME/.config/yabai/init.py" >> /tmp/yabai-init.log 2>&1
touch /tmp/yabai-script-done

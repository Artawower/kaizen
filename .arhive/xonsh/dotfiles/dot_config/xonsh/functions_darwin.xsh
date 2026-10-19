def _bu(args):
    """Brew update + show outdated."""
    ![brew update]
    ![brew outdated]


def aerospace_clear():
    """Close all Aerospace windows with empty titles."""
    aerospace list-windows --all --json \
    | jq -r '.[] | select(."window-title"=="") | ."window-id"' \
    | xargs -n1 aerospace close --window-id
    terminal-notifier "Aerospace Cleanup" -message "Closed empty windows"


aliases['bu'] = _bu

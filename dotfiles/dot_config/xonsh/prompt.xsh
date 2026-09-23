_starship_init = cached_init('starship-init', ['starship', 'init', 'xonsh', '--print-full-init'])
if _starship_init is not None:
    execx(_starship_init)
    del _starship_init

$VI_MODE_INDICATOR = True

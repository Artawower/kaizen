def _limit(args):
    """Run a command under systemd memory/CPU limits: limit <cmd>"""
    cmd_args = list(args)
    if cmd_args and cmd_args[0] in aliases:
        aliased = aliases[cmd_args[0]]
        if isinstance(aliased, list):
            cmd_args = aliased + cmd_args[1:]
        elif isinstance(aliased, str):
            cmd_args = aliased.split() + cmd_args[1:]
    final = [
        'systemd-run', '--user', '--scope',
        '-p', 'MemoryMax=4G',
        '-p', 'CPUWeight=20',
        '-p', 'ManagedOOMMemoryPressure=kill',
        '-p', 'ManagedOOMMemoryPressureLimit=4%',
    ] + cmd_args
    $[ @(final) ]


aliases['limit'] = _limit

def toggle_recording [] {
    let state_file = ($env.TMPDIR | path join "rift-recording-state")
    let recording = ($state_file | path exists)

    if not $recording {
        rift-cli execute config set-outer-gaps 60 10 60 10
        if $env.LAST_EXIT_CODE != 0 { return }

        rift-cli execute load-layout ~/.config/rift/layouts/recording.ron
        if $env.LAST_EXIT_CODE != 0 { return }

        touch $state_file
    } else {
        rift-cli execute config set-outer-gaps 14 24 24 24
        if $env.LAST_EXIT_CODE != 0 { return }

        rm $state_file
    }
}

toggle_recording

def jjbl [] {
    jj bookmark list --color=always
    | lines
    | parse -r '^(?<name>.*?):(?:\x1b\[[0-9;]*m)*\s+(?<change_id>.*?)(?:\x1b\[[0-9;]*m)*\s+(?<commit_id>.*?)(?:\x1b\[[0-9;]*m)*\s+(?<description>.*)$'
}

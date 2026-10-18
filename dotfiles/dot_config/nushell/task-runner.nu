def trun-tasks [] {
    let result = (^runner list --json --schema-version 1 | complete)
    if $result.exit_code != 0 {
        print --stderr $result.stderr
        return []
    }
    try {
        $result.stdout | from json | get tasks
    } catch {
        []
    }
}

def "nu-complete trun tasks" [] {
    let tasks = (trun-tasks)
    let groups = ($tasks | group-by name)
    $tasks | each {|task|
        let group = ($groups | get $task.name)
        let value = if ($group | length) > 1 { $"($task.source):($task.name)" } else { $task.name }
        let description = ($task.description? | default "")
        {value: $value, description: $"[($task.source)] ($description)"}
    }
}

def trun [task?: string@"nu-complete trun tasks"] {
    let tasks = (trun-tasks)
    if ($tasks | is-empty) {
        print "No tasks found."
        return
    }

    if $task != null {
        if ($task | str contains ":") {
            ^run $task
            return
        }

        let matches = ($tasks | where name == $task)
        if ($matches | is-empty) {
            print $"No such task: ($task)"
            return
        }
        if ($matches | length) > 1 {
            let sources = ($matches | get source | str join ", ")
            print $"Task '($task)' is ambiguous: ($sources); use source:name"
            return
        }
        ^run $task
        return
    }

    if (which fzf | is-empty) {
        print --stderr "fzf not found — install fzf or pass a task name directly"
        return
    }

    let lines = ($tasks | enumerate | each {|row|
        let description = ($row.item.description? | default "")
        $"($row.index)\t($row.item.name)\t($row.item.source)\t($description)"
    } | str join (char newline))
    let selection = ($"($lines)(char newline)" | ^fzf --delimiter="\t" --with-nth=2,3,4 --prompt="Run ❯ " --header="COMMAND\tSOURCE\tDESCRIPTION" --reverse --border=rounded --height=60% | complete)
    if $selection.exit_code != 0 or ($selection.stdout | str trim | is-empty) {
        return
    }

    let index = ($selection.stdout | split row "\t" | first | into int)
    let selected = ($tasks | get $index)
    ^run $"($selected.source):($selected.name)"
}

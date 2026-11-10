#!/usr/bin/env nu
# sr - spaced repetition for shell commands, LeetCode problems, and notes.
# Requires Nushell 0.114+. Optional: fzf.
# Database override: $env.SR_DB = '/tmp/sr-test.json'

const grades = [again hard good easy]

def db-path [] {
    let custom = ($env | get -o SR_DB | default '')
    if $custom != '' { $custom } else { [$env.HOME '.local' 'share' 'sr' 'items.json'] | path join }
}

def load-items [] {
    let file = (db-path)
    if ($file | path exists) { open $file } else { [] }
}

def save-items [items: list] {
    let file = (db-path)
    mkdir ($file | path dirname)
    $items | to json --indent 2 | save --force $file
}

def today [] { date now | format date '%Y-%m-%d' }

def date-in [days: int] {
    ((date now) + (1day * $days)) | format date '%Y-%m-%d'
}

def parse-due [due: string] {
    try {
        $due | into datetime --format '%Y-%m-%d' | format date '%Y-%m-%d'
    } catch {
        error make {msg: $'Invalid date ($due), expected YYYY-MM-DD'}
    }
}

def due-items [] {
    let day = (today)
    load-items | where {|item| $item.due <= $day } | sort-by due
}

def show-items [items: list] {
    if ($items | is-empty) {
        print 'No matching items.'
    } else {
        $items | select id due interval title command
    }
}

def item-ids [] {
    load-items | sort-by due | each {|item|
        {value: ($item.id | into string), description: $'($item.due) ($item.title)'}
    }
}

def grade-names [] { $grades }

def pick-item [items: list] {
    if ($items | is-empty) { return null }
    if (which fzf | is-empty) {
        return ($items | input list --fuzzy --display {|item| $'#($item.id) | ($item.due) | ($item.title)'} 'Select an item')
    }
    let tab = (char tab)
    let lines = ($items | each {|item| $'($item.id)($tab)($item.due)($tab)($item.title)' })
    let selected = (try {
        $lines | str join (char newline) | ^fzf --height '40%' --reverse --delimiter (char tab) --with-nth '2,3' --prompt 'sr> ' | str trim
    } catch { '' })
    if $selected == '' { return null }
    let id = ($selected | split row $tab | first | into int)
    $items | where {|item| $item.id == $id } | first
}

def find-item [id?: int] {
    let items = (load-items | sort-by due)
    if $id == null { return (pick-item $items) }
    let matches = ($items | where {|item| $item.id == $id })
    if ($matches | is-empty) {
        error make {msg: $'Item #($id) not found'}
    }
    $matches | first
}

def update-item [item: record] {
    save-items (load-items | each {|row| if $row.id == $item.id { $item } else { $row } })
}

def validate-item [item: record, original: record] {
    if ($item | get -o id) != $original.id { error make {msg: 'id cannot be changed'} }
    for field in [title command due] {
        let value = ($item | get -o $field)
        if ($value | describe) != 'string' or ($value | str trim) == '' {
            error make {msg: $'($field) must be a non-empty string'}
        }
    }
    let interval = ($item | get -o interval)
    if ($interval | describe) != 'int' or $interval < 0 {
        error make {msg: 'interval must be an integer >= 0'}
    }
    $item | merge {due: (parse-due $item.due)}
}

def edit-in-editor [item: record] {
    let file = (mktemp --tmpdir --suffix .nuon)
    $item | reject -o history | to nuon --indent 2 | save --force $file
    let editor = ($env | get -o VISUAL | default ($env | get -o EDITOR | default 'vi') | split row ' ')
    try {
        run-external ($editor | first) ...($editor | skip 1) $file
        let edited = (open --raw $file | from nuon)
        rm $file
        validate-item $edited $item | merge {history: ($item | get -o history | default [])}
    } catch {|err|
        rm -f $file
        error make {msg: $err.msg}
    }
}

def apply-grade [item: record, grade: string] {
    let base = if $item.interval < 1 { 1 } else { $item.interval }
    let interval = match $grade {
        'again' => 1
        'hard' => ($base * 1.2 | math ceil)
        'good' => ($base * 2)
        'easy' => ($base * 3)
    }
    let history = ($item | get -o history | default [])
    let next = ($item | merge {
        interval: $interval
        due: (date-in $interval)
        history: ($history | append [{date: (today), grade: $grade, interval: $interval}])
    })
    update-item $next
    print $'Item #($item.id): ($grade); next review: ($next.due)'
}

def run-item [command: string] {
    # cd cannot change the parent shell directory: open a subshell for cd tasks.
    let script = if ($command | str trim | str starts-with 'cd ') {
        print 'A subshell will open. Type exit when finished.'
        $'($command); nu'
    } else { $command }
    # Leave the terminal attached, so editors and other TUIs stay interactive.
    ^nu -c $script
    $env.LAST_EXIT_CODE == 0
}

# Spaced repetition for commands, problems, and notes.
# Grades: again=1 day, hard=x1.2, good=x2, easy=x3.
# Items without an ID are picked with fzf.
export def main [] {
    print 'Usage: sr add | list | due | review | done | edit | remove'
    print 'Run sr <command> --help for details.'
    print $'Database: (db-path)'
}

# Add an item: sr add "leetctl edit 290" -d 7 -t "LeetCode 290"
export def "sr add" [
    command: string           # Command to run on review
    --days(-d): int = 7       # Initial delay in days
    --title(-t): string = ''  # Display title, defaults to the command
] {
    if $days < 0 { error make {msg: '--days must be >= 0'} }
    if ($command | str trim) == '' { error make {msg: 'Command is empty'} }

    let items = (load-items)
    let id = if ($items | is-empty) { 1 } else { ($items | get id | math max) + 1 }
    let label = if $title == '' { $command } else { $title }
    let item = {
        id: $id
        title: $label
        command: $command
        interval: $days
        due: (date-in $days)
        history: []
    }
    save-items ($items | append [$item])
    print $'Added #($id): ($label); due: ($item.due)'
}

# Show all items
export def "sr list" [] { show-items (load-items | sort-by due) }

# Show today's and overdue items
export def "sr due" [] { show-items (due-items) }

# Pick an item, run its command, and grade it
export def "sr review" [
    --all(-a)     # Include items not yet due
    --manual(-m)  # Grade without running the command
] {
    let items = if $all { load-items | sort-by due } else { due-items }
    if ($items | is-empty) {
        print 'Nothing due. Use --all to include future items.'
        return
    }
    let item = (pick-item $items)
    if $item == null { return }
    print $'Reviewing #($item.id): ($item.title)'
    print $'Command: ($item.command)'
    if $manual {
        input 'Do it yourself, then press Enter to grade (Ctrl+C to cancel)... '
    } else {
        let success = (run-item $item.command)
        if not $success {
            print 'Command failed. Item was not graded.'
            return
        }
    }
    let grade = ($grades | append skip | input list 'How did it go?')
    if $grade == null or $grade == 'skip' { return }
    apply-grade $item $grade
}

# Grade an item without running it
export def "sr done" [
    id?: int@item-ids              # Item ID
    grade?: string@grade-names     # again | hard | good | easy
] {
    if $grade != null and $grade not-in $grades {
        error make {msg: 'Grade must be again, hard, good, or easy'}
    }
    let item = (find-item $id)
    if $item == null { return }
    let grade = if $grade == null { $grades | input list 'How did it go?' } else { $grade }
    if $grade == null { return }
    apply-grade $item $grade
}

# Edit an item; without flags, open it in $VISUAL or $EDITOR
export def "sr edit" [
    id?: int@item-ids       # Item ID
    --title(-t): string     # New title
    --command(-c): string   # New command
    --days(-d): int         # Set the interval and schedule it this many days from today
    --due: string           # Set the next review date, YYYY-MM-DD
] {
    if $days != null and $due != null { error make {msg: 'Use either --days or --due'} }
    let item = (find-item $id)
    if $item == null { return }
    let flags = {title: $title, command: $command}
        | merge (if $days != null { {interval: $days, due: (date-in $days)} } else { {} })
        | merge (if $due != null { {due: $due} } else { {} })
        | transpose key value
        | where value != null
        | transpose -rd
    let updated = if ($flags | is-empty) {
        edit-in-editor $item
    } else {
        validate-item ($item | merge $flags) $item
    }
    update-item $updated
    print $'Updated #($updated.id): ($updated.title); due: ($updated.due)'
}

# Delete an item
export def "sr remove" [
    id?: int@item-ids  # Item ID
] {
    let item = (find-item $id)
    if $item == null { return }
    save-items (load-items | where {|row| $row.id != $item.id })
    print $'Removed #($item.id): ($item.title)'
}

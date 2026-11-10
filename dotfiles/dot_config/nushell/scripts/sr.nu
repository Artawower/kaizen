#!/usr/bin/env nu
# sr - spaced repetition for shell commands, LeetCode problems, and notes.
# Requires Nushell 0.114+. Optional: fzf.
# Database override: $env.SR_DB = '/tmp/sr-test.json'

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

def add-item [command: string, days: int, title: string] {
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

def grade-item [id: int, grade: string] {
    if $grade not-in [again hard good easy] {
        error make {msg: 'Grade must be again, hard, good, or easy'}
    }
    let items = (load-items)
    let matches = ($items | where {|item| $item.id == $id })
    if ($matches | is-empty) {
        error make {msg: $'Item #($id) not found'}
    }
    let item = ($matches | first)
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
    let updated = ($items | each {|row| if $row.id == $id { $next } else { $row } })
    save-items $updated
    print $'Item #($id): ($grade); next review: ($next.due)'
}

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

def review-items [all: bool, manual: bool] {
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
    let grade = ([again hard good easy skip] | input list 'How did it go?')
    if $grade == null or $grade == 'skip' { return }
    grade-item $item.id $grade
}

def remove-item [id: int] {
    let items = (load-items)
    let remaining = ($items | where {|item| $item.id != $id })
    if ($remaining | length) == ($items | length) {
        error make {msg: $'Item #($id) not found'}
    }
    save-items $remaining
    print $'Removed #($id)'
}

def show-help [] {
    print 'sr - spaced repetition for commands, problems, and notes'
    print 'Usage:'
    print '  sr add "leetctl edit 290" --days 7 --title "LeetCode 290"'
    print '  sr list                      Show all items'
    print '  sr due                       Show today/overdue items'
    print '  sr review                    Pick with fzf, execute, grade'
    print '  sr review --all              Include future items'
    print '  sr review --manual           Grade without executing'
    print '  sr done 1 good               Grade by ID'
    print '  sr remove 1                  Delete by ID'
    print '  sr help                      Show this message'
    print 'Flags: -d/--days, -t/--title, -a/--all, -m/--manual'
    print 'Grades: again=1 day, hard=x1.2, good=x2, easy=x3'
    print $'Database: (db-path)'
}

export def main [
    action?: string         # add | list | due | review | done | remove | help
    value?: any             # Command for add, ID for done/remove
    grade?: string          # Grade for done
    --days(-d): int = 7     # Initial delay in days
    --title(-t): string = '' # Display title
    --all(-a)               # Include items not yet due
    --manual(-m)            # Do not execute the command
] {
    match ($action | default 'help') {
        'add' => {
            if $value == null { show-help } else {
                add-item ($value | into string) $days $title
            }
        }
        'list' => { show-items (load-items | sort-by due) }
        'due' => { show-items (due-items) }
        'review' => { review-items $all $manual }
        'done' => {
            if $value == null or $grade == null { show-help } else {
                grade-item ($value | into int) $grade
            }
        }
        'remove' => {
            if $value == null { show-help } else {
                remove-item ($value | into int)
            }
        }
        'help' => { show-help }
        _ => { show-help }
    }
}

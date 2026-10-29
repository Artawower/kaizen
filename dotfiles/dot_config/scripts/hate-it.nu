const NEW_KEY = "new"
const FILE_PATH = "~/tmp/hate.json"

def main [
  --list
] {
  let hateList = open ($FILE_PATH | path expand)


  if ($list) {
    print ($hateList | sort-by count | where { |row| ($row.solved? | default false) != true })
    return
  }


  let hate = $hateList
  | where { |row| ($row.solved? | default false) != true }
  | sort-by count --reverse
  | each { |row| $"[($row.type)]\(($row.count)\) ($row.hate)" }
  | append $NEW_KEY


  let reason = $hate | fzf | str replace -r '^\[[^\]]*\]\s*\d+\s+' '' | str trim


  if ($reason != $NEW_KEY) {
    let updated = $hateList
    | update count { |row|
       if ($row.hate == $reason) {
         $row.count + 1
       } else {
         $row.count
       }
    }

    saveHates $updated
    return
  }


  let choices = $hateList | get type | uniq


  let choiceList = (
    $choices
    | enumerate
    | each { |row| $"($row.index + 1): ($row.item)" }
    | str join (char nl)
  )

  print "Pick category or create a new one:"
  print $choiceList

  let choice = (input "> ")

  let number = (try { $choice | into int } catch { null })

  let category = if $number != null and $number >= 1 and $number <= ($choices | length) {
    $choices | get ($number - 1)
  } else {
    $choice
  }

  print $category

  let description = (input "Privide description: ")


  let updatedList = $hateList | append {
     type: $category
     hate: $description
     count: 1
  }

  print $updatedList
  
  saveHates $updatedList
}



def saveHates [data] {
  $data
    | save -f ($FILE_PATH | path expand)
}

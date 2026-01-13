use api.nu [format-date]

# Display key-value pair
export def display-kv [key: string, val: any] {
  print $"(ansi cyan)($key):(ansi reset) ($val)"
}

# Display section header
export def display-section [title: string] {
  print $"(ansi cyan)($title):(ansi reset)"
}

export def truncate [n: int] {
  let s = $in
  if ($s | str length) > $n {
    let limit = ($n - 1)
    let sub = ($s | str substring 0..$limit)
    $"($sub)..."
  } else { 
    $s 
  }
}

# Prompt for text input
export def prompt [
  msg: string
  --required
] {
  let val = (input $msg)
  if $required and ($val | is-empty) {
    error make { msg: $"$msg | str replace ': $' '') is required" }
  }
  $val
}

# Prompt for selection
export def prompt-select [
  msg: string
  options: list<string>
] {
  let choice = ($options | input list $msg)
  if $choice == null { error make { msg: "No selection made" } }
  $choice
}

# Parse row specification (e.g., "1,3-5" -> [0, 2, 3, 4])
# Uses 1-based indexing for input
export def parse-row-spec [spec: string] {
  $spec 
  | split row "," 
  | each { |part| 
    if ($part | str contains "-") {
      let range = ($part | split row "-")
      let start = ($range.0 | into int) - 1
      let end = ($range.1 | into int) - 1
      $start..$end
    } else {
      ($part | into int) - 1
    }
  }
  | flatten
  | uniq
  | sort
}

# Apply view transformations: sort, filter rows, select columns
export def apply-view [
  --cols: string
  --rows: string
  --sort: string
] {
  let input = $in
  mut data = $input

  if ($data | is-empty) { return $data }

  # Sort
  if $sort != null {
    $data = ($data | sort-by $sort)
  }

  # Filter rows
  if $rows != null {
    let indices = (parse-row-spec $rows)
    $data = ($data | enumerate | where { |x| $x.index in $indices } | get item)
  }

  # Select columns (case-insensitive)
  if $cols != null {
    let available = ($data | columns)
    let requested = ($cols | split row "," | each { str trim })
    let final_cols = ($requested | each { |req| 
      let match = ($available | where { |c| ($c | str downcase) == ($req | str downcase) } | first)
      if $match == null { $req } else { $match } 
    })
    $data = ($data | select ...$final_cols)
  }

  $data
}

# Render issue details
export def render-issue [i: record] {
  print $"(ansi green_bold)($i.identifier)(ansi reset) - ($i.title)"
  display-kv "Status" $i.state.name
  display-kv "URL" $i.url
  if ($i.parent? | default null) != null { display-kv "Epic" $"$i.parent.identifier) - ($i.parent.title)" }
  if ($i.assignee? | default null) != null { display-kv "Assignee" $i.assignee.name }
  if ($i.labels?.nodes? | default [] | length) > 0 { display-kv "Labels" ($i.labels.nodes | get name | str join ", ") }
  if ($i.description? | default "") != "" {
    print ""
    display-section "Description"
    print $i.description 
  }
  
  if ($i.children?.nodes? | default [] | length) > 0 {
    print ""
    display-section "Sub-issues"
    $i.children.nodes | each { |c| { ID: $c.identifier, Status: $c.state.name, Title: $c.title } } | print
  }

  if ($i.relations?.nodes? | default [] | length) > 0 {
    let rels = $i.relations.nodes
    let blocks = $rels | where type == "blocks"
    let blocked_by = $rels | where type == "blocked_by"

    if ($blocked_by | length) > 0 {
      print ""
      display-section "Blocked by"
      $blocked_by | each { |r| {
        ID: $r.relatedIssue.identifier
        Status: $r.relatedIssue.state.name
        Title: $r.relatedIssue.title
      }} | print
    }

    if ($blocks | length) > 0 {
      print ""
      display-section "Blocks"
      $blocks | each { |r| {
        ID: $r.relatedIssue.identifier
        Status: $r.relatedIssue.state.name
        Title: $r.relatedIssue.title
      }} | print
    }
  }
}

# Render comments
export def render-comments [comments: list] {
  if ($comments | length) == 0 { print "No comments"; return }

  for c in $comments {
    let date = ($c.createdAt | format-date "%Y-%m-%d %H:%M")
    print $"(ansi cyan)($c.user?.name? | default 'Unknown')(ansi reset) - ($date)\n($c.body)\n"
  }
  print $"$comments | length) comments"
}
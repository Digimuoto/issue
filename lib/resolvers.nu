# Entity resolution helpers

use api.nu [exit-error, linear-query]

# Get team (errors if multiple teams and no team specified)
export def get-team [team_name?: string] {
  let data = (linear-query r#'{ teams { nodes { id name } } }'#)
  let teams = $data.teams.nodes

  if $team_name != null and $team_name != "" {
    let t = ($teams | where name == $team_name | first)
    if $t == null { exit-error $"Team '($team_name)' not found" }
    $t
  } else if ($teams | length) == 1 {
    $teams.0
  } else {
    # Interactive selection
    let choice = ($teams | get name | input list "Select Team:")
    if $choice == null { exit-error "No team selected" }
    $teams | where name == $choice | first
  }
}

# Get current user
export def get-viewer [] {
  let data = (linear-query r#'{ viewer { id name email } }'#)
  $data.viewer
}

# Resolve user: "me" -> viewer, otherwise search by name/email
export def resolve-user [name: string] {
  let user = if $name == "me" {
    get-viewer
  } else {
    let data = (linear-query r#'{ users { nodes { id name email } } }'#)
    $data.users.nodes
    | where { |u| ($u.name | str contains -i $name) or ($u.email | str contains -i $name) }
    | first
  }
  if $user == null { exit-error $"User '($name)' not found" }
  $user
}

# Get issue UUID from identifier (e.g., DIG-88) or title search
export def get-issue-uuid [id_or_title: string] {
  # 1. Try direct lookup (ID or UUID)
  let data = (linear-query r#'query($id: String!) { issue(id: $id) { id identifier } }'# { id: $id_or_title })
  if $data.issue != null { return $data.issue.id }

  # 2. Search by title
  let search = (linear-query r#'query($term: String!) {
    issues(filter: { title: { contains: $term } }, first: 5) {
      nodes { id identifier title }
    }
  }'# { term: $id_or_title })

  let found = $search.issues.nodes
  
  if ($found | length) == 0 {
    exit-error $"Issue '($id_or_title)' not found"
  }
  
  if ($found | length) == 1 {
    return $found.0.id
  }
  
  # Check for exact case-insensitive title match
  let exact = ($found | where { |i| ($i.title | str downcase) == ($id_or_title | str downcase) })
  if ($exact | length) == 1 {
    return $exact.0.id
  }

  let suggestions = ($found | each { |i| $"  ($i.identifier): ($i.title)" } | str join "\n")
  exit-error $"Multiple issues found for '($id_or_title)':\n($suggestions)"
}

# Get document UUID from slug
export def get-doc-uuid [id: string] {
  let data = (linear-query r#'query($id: String!) { document(id: $id) { id title } }'# { id: $id })
  if $data.document == null { exit-error $"Document '($id)' not found" }
  $data.document.id
}

# Resolve project by name
export def resolve-project [name: string] {
  let data = (linear-query r#'query($name: String!) { projects(filter: { name: { eq: $name } }) { nodes { id name } } }'# { name: $name })
  let p = $data.projects.nodes | first
  if $p == null { exit-error $"Project '($name)' not found" }
  $p
}

# Resolve label names to IDs (case-insensitive)
export def resolve-labels [names: list<string>] {
  let data = (linear-query r#'{ issueLabels(first: 250) { nodes { id name } } }'#)
  let all = $data.issueLabels.nodes
  let normalized = $names | each { str trim | str downcase }
  let found = $all | where { |l| ($l.name | str downcase) in $normalized }
  let found_names = $found | get name | each { str downcase }
  let missing = $normalized | where { |n| not ($n in $found_names) }
  if ($missing | length) > 0 {
    exit-error $"Unknown labels: ($missing | str join ', ')"
  }
  $found | get id
}

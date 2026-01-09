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
    exit-error $"Multiple teams found: ($teams | get name | str join ', '). Use --team <name>"
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

# Get issue UUID from identifier (e.g., DIG-88)
export def get-issue-uuid [id: string] {
  let data = (linear-query r#'query($id: String!) { issue(id: $id) { id identifier } }'# { id: $id })
  if $data.issue == null { exit-error $"Issue '($id)' not found" }
  $data.issue.id
}

# Get document UUID from slug
export def get-doc-uuid [id: string] {
  let data = (linear-query r#'query($id: String!) { document(id: $id) { id title } }'# { id: $id })
  if $data.document == null { exit-error $"Document '($id)' not found" }
  $data.document.id
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
    exit-error $"Unknown label(s): ($missing | str join ', ')"
  }
  $found | get id
}

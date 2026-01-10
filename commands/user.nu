# User commands

use ../lib/api.nu [exit-error, linear-query]

# User management
export def "main user" [] {
  print "User commands - use 'issue user --help' for usage"
}

# Show current authenticated user
export def "main me" [
  --json (-j)  # Output as JSON
] {
  let data = (linear-query r#'{ viewer { id name email displayName admin active createdAt } }'#)
  let v = $data.viewer

  if $json {
    return ({
      name: $v.name
      email: $v.email
      displayName: ($v.displayName | default null)
      admin: $v.admin
      active: $v.active
      createdAt: $v.createdAt
    } | to json)
  }

  print $"(ansi green_bold)($v.name)(ansi reset)"
  print $"(ansi cyan)Email:(ansi reset) ($v.email)"
  if $v.displayName != null and $v.displayName != $v.name { print $"(ansi cyan)Display:(ansi reset) ($v.displayName)" }
  print $"(ansi cyan)Admin:(ansi reset) ($v.admin)"
  print $"(ansi cyan)Active:(ansi reset) ($v.active)"
  print $"(ansi cyan)Member since:(ansi reset) ($v.createdAt | into datetime | format date '%Y-%m-%d')"
}

# List users
export def "main user list" [
  --team (-T): string  # Filter by team name
  --json (-j)          # Output as JSON
] {
  let data = if $team != null {
    let team_data = (linear-query r#'{ teams { nodes { id name } } }'#)
    let team_rec = $team_data.teams.nodes | where name == $team | first
    if $team_rec == null { exit-error $"Team '($team)' not found" }

    linear-query r#'
      query($teamId: String!) {
        team(id: $teamId) { members { nodes { id name email displayName active } } }
      }
    '# { teamId: $team_rec.id }
    | get team.members
  } else {
    linear-query r#'{ users { nodes { id name email displayName active } } }'#
    | get users
  }

  let result = $data.nodes | each { |u| {
    name: $u.name
    email: $u.email
    displayName: ($u.displayName | default null)
    active: $u.active
  }}

  if $json { $result | to json } else {
    $result | each { |u| { Name: $u.name, Email: $u.email, Display: ($u.displayName | default "-"), Active: $u.active } }
  }
}

# Show user details
export def "main user show" [
  query: string  # User name or email to search
  --json (-j)    # Output as JSON
] {
  let data = (linear-query r#'{ users { nodes { id name email displayName admin active createdAt assignedIssues(first: 10, filter: { state: { type: { in: ["started", "unstarted"] } } }) { nodes { identifier title state { name } } } } } }'#)

  let user = $data.users.nodes | where { |u| ($u.name | str contains -i $query) or ($u.email | str contains -i $query) } | first
  if $user == null { exit-error $"User '($query)' not found" }

  if $json {
    return ({
      name: $user.name
      email: $user.email
      displayName: ($user.displayName | default null)
      admin: $user.admin
      active: $user.active
      createdAt: $user.createdAt
      assignedIssues: ($user.assignedIssues.nodes | each { |i| { id: $i.identifier, title: $i.title, status: $i.state.name } })
    } | to json)
  }

  print $"(ansi green_bold)($user.name)(ansi reset)"
  print $"(ansi cyan)Email:(ansi reset) ($user.email)"
  if $user.displayName != null and $user.displayName != $user.name { print $"(ansi cyan)Display:(ansi reset) ($user.displayName)" }
  print $"(ansi cyan)Admin:(ansi reset) ($user.admin)"
  print $"(ansi cyan)Active:(ansi reset) ($user.active)"
  print $"(ansi cyan)Member since:(ansi reset) ($user.createdAt | into datetime | format date '%Y-%m-%d')"

  if ($user.assignedIssues.nodes | length) > 0 {
    print $"\n(ansi cyan)Active Issues:(ansi reset)"
    $user.assignedIssues.nodes | each { |i| { ID: $i.identifier, Status: $i.state.name, Title: $i.title } } | print
  }
}

# Team commands

use ../lib/api.nu [exit-error, linear-query, display-kv]

# Team management
export def "main team" [] {
  print "Team commands - use 'issue team --help' for usage"
}

# List teams
export def "main team list" [
  --json (-j)  # Output as JSON
] {
  let data = (linear-query r#'{ teams { nodes { id name key description timezone } } }'#)

  let result = $data.teams.nodes | each { |t| {
    key: $t.key
    name: $t.name
    timezone: ($t.timezone | default null)
    description: ($t.description | default null)
  }}

  if $json { $result | to json } else {
    $result | each { |t| { Key: $t.key, Name: $t.name, Timezone: ($t.timezone | default "-"), Description: ($t.description | default "-") } }
  }
}

# Show team details
export def "main team show" [
  name: string  # Team name or key
  --json (-j)   # Output as JSON
] {
  let data = (linear-query r#'
    query {
      teams { nodes { id name key description timezone cycleStartDay cycleDuration defaultIssueEstimate members { nodes { name email } } } }
    }
  '#)

  let team = $data.teams.nodes | where { |t| $t.name == $name or $t.key == $name } | first
  if $team == null { exit-error $"Team '($name)' not found" }

  if $json {
    return ({
      key: $team.key
      name: $team.name
      description: ($team.description | default null)
      timezone: ($team.timezone | default null)
      cycleDuration: ($team.cycleDuration | default null)
      cycleStartDay: ($team.cycleStartDay | default null)
      defaultIssueEstimate: ($team.defaultIssueEstimate | default null)
      members: ($team.members.nodes | each { |m| { name: $m.name, email: $m.email } })
    } | to json)
  }

  print $"(ansi green_bold)($team.name)(ansi reset) [($team.key)]"
  if $team.description != null { display-kv "Description" $team.description }
  display-kv "Timezone" ($team.timezone | default '-')
  display-kv "Cycle Duration" $"($team.cycleDuration | default '-') weeks"
  display-kv "Cycle Start Day" ($team.cycleStartDay | default '-')
  display-kv "Default Estimate" ($team.defaultIssueEstimate | default '-')

  if ($team.members.nodes | length) > 0 {
    print ""
    display-kv "Members" ""
    $team.members.nodes | each { |m| { Name: $m.name, Email: $m.email } } | print
  }
}

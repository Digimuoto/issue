# Team commands

use ../lib/api.nu [exit-error, linear-query]

# Team management
export def "main team" [] {
  print "Team commands - use 'issue team --help' for usage"
}

# List teams
export def "main team list" [] {
  let data = (linear-query r#'{ teams { nodes { id name key description timezone } } }'#)

  $data.teams.nodes | each { |t| {
    Key: $t.key
    Name: $t.name
    Timezone: ($t.timezone | default "-")
    Description: ($t.description | default "-")
  }}
}

# Show team details
export def "main team show" [
  name: string  # Team name or key
] {
  let data = (linear-query r#'
    query {
      teams { nodes { id name key description timezone cycleStartDay cycleDuration defaultIssueEstimate members { nodes { name email } } } }
    }
  '#)

  let team = $data.teams.nodes | where { |t| $t.name == $name or $t.key == $name } | first
  if $team == null { exit-error $"Team '($name)' not found" }

  print $"(ansi green_bold)($team.name)(ansi reset) [($team.key)]"
  if $team.description != null { print $"(ansi cyan)Description:(ansi reset) ($team.description)" }
  print $"(ansi cyan)Timezone:(ansi reset) ($team.timezone | default '-')"
  print $"(ansi cyan)Cycle Duration:(ansi reset) ($team.cycleDuration | default '-') weeks"
  print $"(ansi cyan)Cycle Start Day:(ansi reset) ($team.cycleStartDay | default '-')"
  print $"(ansi cyan)Default Estimate:(ansi reset) ($team.defaultIssueEstimate | default '-')"

  if ($team.members.nodes | length) > 0 {
    print $"\n(ansi cyan)Members:(ansi reset)"
    $team.members.nodes | each { |m| { Name: $m.name, Email: $m.email } } | print
  }
}

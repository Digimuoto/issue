# Cycle/Sprint commands

use ../lib/api.nu [exit-error, linear-query, truncate]
use ../lib/resolvers.nu [get-team]

# Show current sprint
export def "main cycle" [
  --all (-a)      # Show all cycles
  --team (-T): string  # Team name (required if multiple teams)
] {
  let team_rec = (get-team $team)

  let data = (linear-query r#'
    query($teamId: String!) {
      team(id: $teamId) {
        cycles(first: 10) {
          nodes { id number name startsAt endsAt progress issues { nodes { identifier title state { name type } } } }
        }
        activeCycle { id number name startsAt endsAt progress issues { nodes { identifier title state { name type } } } }
      }
    }
  '# { teamId: $team_rec.id })

  if $all {
    let active_id = ($data.team.activeCycle?.id? | default "")
    return ($data.team.cycles.nodes | each { |c| {
      Cycle: $c.number
      Active: ($c.id == $active_id)
      Name: ($c.name | default "-")
      Start: ($c.startsAt | into datetime | format date '%Y-%m-%d')
      End: ($c.endsAt | into datetime | format date '%Y-%m-%d')
      Progress: ($c.progress * 100 | math round)
      Issues: ($c.issues.nodes | length)
    }})
  }

  let active = $data.team.activeCycle
  if $active == null { print "No active cycle"; return }

  print $"(ansi green_bold)Cycle ($active.number)(ansi reset) - ($active.name | default 'Unnamed')"
  print $"(ansi cyan)Period:(ansi reset) ($active.startsAt | into datetime | format date '%Y-%m-%d') → ($active.endsAt | into datetime | format date '%Y-%m-%d')"
  print $"(ansi cyan)Progress:(ansi reset) ($active.progress * 100 | math round)%\n"

  let issues = $active.issues.nodes
  let done = $issues | where { |i| $i.state.type == "completed" } | length
  let wip = $issues | where { |i| $i.state.type == "started" } | length
  let todo = $issues | where { |i| $i.state.type in ["unstarted", "backlog"] } | length

  print $"(ansi cyan)Issues:(ansi reset) ($done) done, ($wip) in progress, ($todo) todo\n"

  if ($issues | length) > 0 {
    $issues | each { |i| { ID: $i.identifier, Status: $i.state.name, Title: ($i.title | truncate 50) } } | print
  }
}

# List all cycles
export def "main cycle list" [
  --team (-T): string  # Team name (required if multiple teams)
  --past (-p)          # Include past cycles
  --limit (-n): int = 20  # Max cycles to fetch
] {
  let team_rec = (get-team $team)

  let data = (linear-query r#'
    query($teamId: String!, $limit: Int!) {
      team(id: $teamId) {
        cycles(first: $limit) {
          nodes { id number name startsAt endsAt progress }
        }
        activeCycle { id }
      }
    }
  '# { teamId: $team_rec.id, limit: $limit })

  let active_id = ($data.team.activeCycle?.id? | default "")
  let now = (date now)

  $data.team.cycles.nodes
  | where { |c|
      if $past { true } else {
        let end = ($c.endsAt | into datetime)
        $end >= $now
      }
    }
  | each { |c| {
    Cycle: $c.number
    Active: (if $c.id == $active_id { "●" } else { "" })
    Name: ($c.name | default "-")
    Start: ($c.startsAt | into datetime | format date '%Y-%m-%d')
    End: ($c.endsAt | into datetime | format date '%Y-%m-%d')
    Progress: ($"($c.progress * 100 | math round)%")
  }}
}

# Show cycle details
export def "main cycle show" [
  number: int            # Cycle number
  --team (-T): string    # Team name (required if multiple teams)
] {
  let team_rec = (get-team $team)

  let data = (linear-query r#'
    query($teamId: String!) {
      team(id: $teamId) {
        cycles(first: 50) {
          nodes {
            id number name description startsAt endsAt progress
            issues { nodes { identifier title state { name type } priority assignee { name } } }
          }
        }
      }
    }
  '# { teamId: $team_rec.id })

  let cycle = $data.team.cycles.nodes | where { |c| $c.number == $number } | first
  if $cycle == null { exit-error $"Cycle ($number) not found" }

  print $"(ansi green_bold)Cycle ($cycle.number)(ansi reset) - ($cycle.name | default 'Unnamed')"
  print $"(ansi cyan)Period:(ansi reset) ($cycle.startsAt | into datetime | format date '%Y-%m-%d') → ($cycle.endsAt | into datetime | format date '%Y-%m-%d')"
  print $"(ansi cyan)Progress:(ansi reset) ($cycle.progress * 100 | math round)%"
  if $cycle.description != null and $cycle.description != "" { print $"\n(ansi cyan)Description:(ansi reset)\n($cycle.description)" }

  let issues = $cycle.issues.nodes
  let done = $issues | where { |i| $i.state.type == "completed" } | length
  let wip = $issues | where { |i| $i.state.type == "started" } | length
  let todo = $issues | where { |i| $i.state.type in ["unstarted", "backlog"] } | length
  let canceled = $issues | where { |i| $i.state.type == "canceled" } | length

  print $"\n(ansi cyan)Summary:(ansi reset) ($done) done, ($wip) in progress, ($todo) todo, ($canceled) canceled"

  if ($issues | length) > 0 {
    print $"\n(ansi cyan)Issues:(ansi reset)"
    $issues | each { |i| {
      ID: $i.identifier
      Status: $i.state.name
      Priority: $i.priority
      Assignee: ($i.assignee?.name? | default "-")
      Title: ($i.title | truncate 40)
    }} | print
  }
}

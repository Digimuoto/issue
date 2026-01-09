# Cycle/Sprint commands

use ../lib/api.nu [linear-query, truncate]
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

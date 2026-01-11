# Cycle/Sprint commands

use ../lib/api.nu [exit-error, linear-query, truncate, display-kv, display-section, format-date]
use ../lib/resolvers.nu [get-team]

# Show current sprint
export def "main cycle" [
  --all (-a)           # Show all cycles
  --team (-T): string  # Team name (required if multiple teams)
  --json (-j)          # Output as JSON
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
    let result = $data.team.cycles.nodes | each { |c| {
      number: $c.number
      active: ($c.id == $active_id)
      name: ($c.name | default null)
      startsAt: $c.startsAt
      endsAt: $c.endsAt
      progress: ($c.progress * 100 | math round)
      issueCount: ($c.issues.nodes | length)
    }}
    if $json { return ($result | to json) }
    return ($result | each { |c| {
      Cycle: $c.number
      Active: $c.active
      Name: ($c.name | default "-")
      Start: ($c.startsAt | format-date)
      End: ($c.endsAt | format-date)
      Progress: $c.progress
      Issues: $c.issueCount
    }})
  }

  let active = $data.team.activeCycle
  if $active == null {
    if $json { print "null" } else { print "No active cycle" }
    return
  }

  let issues = $active.issues.nodes
  let done = $issues | where { |i| $i.state.type == "completed" } | length
  let wip = $issues | where { |i| $i.state.type == "started" } | length
  let todo = $issues | where { |i| $i.state.type in ["unstarted", "backlog"] } | length

  if $json {
    return ({
      number: $active.number
      name: ($active.name | default null)
      startsAt: $active.startsAt
      endsAt: $active.endsAt
      progress: ($active.progress * 100 | math round)
      summary: { done: $done, inProgress: $wip, todo: $todo }
      issues: ($issues | each { |i| { id: $i.identifier, title: $i.title, status: $i.state.name } })
    } | to json)
  }

  print $"(ansi green_bold)Cycle ($active.number)(ansi reset) - ($active.name | default 'Unnamed')"
  display-kv "Period" $"($active.startsAt | format-date) → ($active.endsAt | format-date)"
  display-kv "Progress" $"($active.progress * 100 | math round)%"
  print ""

  display-section "Issues"
  print $"($done) done, ($wip) in progress, ($todo) todo\n"

  if ($issues | length) > 0 {
    $issues | each { |i| { ID: $i.identifier, Status: $i.state.name, Title: ($i.title | truncate 50) } } | print
  }
}

# List all cycles
export def "main cycle list" [
  --team (-T): string     # Team name (required if multiple teams)
  --past (-p)             # Include past cycles
  --limit (-n): int = 20  # Max cycles to fetch
  --json (-j)             # Output as JSON
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

  let result = $data.team.cycles.nodes
  | where { |c|
      if $past { true } else {
        let end = ($c.endsAt | into datetime)
        $end >= $now
      }
    }
  | each { |c| {
    number: $c.number
    active: ($c.id == $active_id)
    name: ($c.name | default null)
    startsAt: $c.startsAt
    endsAt: $c.endsAt
    progress: ($c.progress * 100 | math round)
  }}

  if $json { $result | to json } else {
    $result | each { |c| {
      Cycle: $c.number
      Active: (if $c.active { "●" } else { "" })
      Name: ($c.name | default "-")
      Start: ($c.startsAt | format-date)
      End: ($c.endsAt | format-date)
      Progress: $"($c.progress)%"
    }}
  }
}

# Show cycle details
export def "main cycle show" [
  number: int            # Cycle number
  --team (-T): string    # Team name (required if multiple teams)
  --json (-j)            # Output as JSON
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

  let issues = $cycle.issues.nodes
  let done = $issues | where { |i| $i.state.type == "completed" } | length
  let wip = $issues | where { |i| $i.state.type == "started" } | length
  let todo = $issues | where { |i| $i.state.type in ["unstarted", "backlog"] } | length
  let canceled = $issues | where { |i| $i.state.type == "canceled" } | length

  if $json {
    return ({
      number: $cycle.number
      name: ($cycle.name | default null)
      description: ($cycle.description | default null)
      startsAt: $cycle.startsAt
      endsAt: $cycle.endsAt
      progress: ($cycle.progress * 100 | math round)
      summary: { done: $done, inProgress: $wip, todo: $todo, canceled: $canceled }
      issues: ($issues | each { |i| { id: $i.identifier, title: $i.title, status: $i.state.name, priority: $i.priority, assignee: ($i.assignee?.name? | default null) } })
    } | to json)
  }

  print $"(ansi green_bold)Cycle ($cycle.number)(ansi reset) - ($cycle.name | default 'Unnamed')"
  display-kv "Period" $"($cycle.startsAt | format-date) → ($cycle.endsAt | format-date)"
  display-kv "Progress" $"($cycle.progress * 100 | math round)%"
  if $cycle.description != null and $cycle.description != "" { 
    print ""
    display-section "Description"
    print $cycle.description 
  }

  print ""
  display-kv "Summary" $"($done) done, ($wip) in progress, ($todo) todo, ($canceled) canceled"

  if ($issues | length) > 0 {
    print ""
    display-section "Issues"
    $issues | each { |i| {
      ID: $i.identifier
      Status: $i.state.name
      Priority: $i.priority
      Assignee: ($i.assignee?.name? | default "-")
      Title: ($i.title | truncate 40)
    }} | print
  }
}

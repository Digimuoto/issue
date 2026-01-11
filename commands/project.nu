# Project commands

use ../lib/api.nu [exit-error, linear-query, truncate, display-kv, display-section]
use ../lib/resolvers.nu [resolve-project]

# Project management
export def "main project" [] {
  print "Project commands - use 'issue project --help' for usage"
}

# List projects
export def "main project list" [
  --all (-a)   # Include completed/canceled projects
  --json (-j)  # Output as JSON
] {
  let filter = if $all { {} } else { { state: { in: ["planned", "started", "paused"] } } }

  let data = (linear-query r#'
    query($filter: ProjectFilter) {
      projects(filter: $filter, first: 50) {
        nodes {
          id name state progress
          startDate targetDate
          lead { name }
          teams { nodes { name } }
        }
      }
    }
  '# { filter: $filter })

  let result = $data.projects.nodes | each { |p| {
    name: $p.name
    state: $p.state
    progress: ($p.progress * 100 | math round)
    lead: ($p.lead?.name? | default null)
    teams: ($p.teams.nodes | get name)
    startDate: ($p.startDate | default null)
    targetDate: ($p.targetDate | default null)
  }}

  if $json { $result | to json } else {
    $result | each { |p| {
      Name: ($p.name | truncate 35)
      State: $p.state
      Progress: $"($p.progress)%"
      Lead: ($p.lead | default "-")
      Teams: ($p.teams | str join ", ")
      Start: ($p.startDate | default "-")
      Target: ($p.targetDate | default "-")
    }}
  }
}

# Show project details
export def "main project show" [
  name: string  # Project name
  --json (-j)   # Output as JSON
] {
  # Resolve project ID
  let proj = (resolve-project $name)

  # Now fetch full details for this specific project
  let data = (linear-query r#'
    query($id: String!) {
      project(id: $id) {
        id name state description progress
        startDate targetDate
        lead { name }
        teams { nodes { name } }
        members { nodes { name } }
        issues(first: 30) { nodes { identifier title state { name } } }
      }
    }
  '# { id: $proj.id })

  let project = $data.project
  if $project == null { exit-error $"Project '($name)' not found" }

  if $json {
    return ({
      name: $project.name
      state: $project.state
      description: ($project.description | default null)
      progress: ($project.progress * 100 | math round)
      startDate: ($project.startDate | default null)
      targetDate: ($project.targetDate | default null)
      lead: ($project.lead?.name? | default null)
      teams: ($project.teams.nodes | get name)
      members: ($project.members.nodes | get name)
      issues: ($project.issues.nodes | each { |i| { id: $i.identifier, title: $i.title, status: $i.state.name } })
    } | to json)
  }

  print $"(ansi green_bold)($project.name)(ansi reset)"
  display-kv "State" $project.state
  display-kv "Progress" $"($project.progress * 100 | math round)%"
  if $project.lead != null { display-kv "Lead" $project.lead.name }
  if ($project.teams.nodes | length) > 0 { display-kv "Teams" ($project.teams.nodes | get name | str join ', ') }
  if $project.startDate != null { display-kv "Start" $project.startDate }
  if $project.targetDate != null { display-kv "Target" $project.targetDate }
  if $project.description != null and $project.description != "" { 
    print ""
    display-section "Description"
    print $project.description 
  }

  if ($project.members.nodes | length) > 0 {
    print ""
    display-kv "Members" ($project.members.nodes | get name | str join ', ')
  }

  if ($project.issues.nodes | length) > 0 {
    print ""
    display-section "Issues"
    $project.issues.nodes | each { |i| { ID: $i.identifier, Status: $i.state.name, Title: ($i.title | truncate 50) } } | print
  }
}

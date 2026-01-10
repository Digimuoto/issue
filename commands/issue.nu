# Issue commands

use ../lib/api.nu [exit-error, linear-query, truncate, map-status]
use ../lib/resolvers.nu [get-team, resolve-user, get-issue-uuid, resolve-labels]

# List issues with filters
export def "main list" [
  --status (-s): string    # Filter: backlog, todo, inprogress, done, canceled
  --label (-l): string     # Filter by label name
  --epic (-e): string      # Filter by parent epic (e.g., DIG-80)
  --project (-p): string   # Filter by project name
  --assignee (-a): string  # Filter by assignee (use "me" for yourself)
  --cycle (-c): string     # Filter by cycle name or "current" for active sprint
  --blocked (-b)           # Only show issues that are blocked
  --blocking (-B)          # Only show issues that block others
  --limit (-n): int = 50   # Max issues to fetch
  --json (-j)              # Output as JSON
] {
  let filter = ({}
    | merge (if $status != null { { state: { name: { eq: (map-status $status) } } } } else { {} })
    | merge (if $label != null { { labels: { name: { eq: $label } } } } else { {} })
    | merge (if $epic != null { { parent: { id: { eq: (get-issue-uuid $epic) } } } } else { {} })
    | merge (if $project != null { { project: { name: { eq: $project } } } } else { {} })
    | merge (if $assignee != null {
        let user = (resolve-user $assignee)
        { assignee: { id: { eq: $user.id } } }
      } else { {} })
    | merge (if $cycle != null {
        let cycle_id = if $cycle == "current" {
          let team = (get-team)
          let data = (linear-query r#'
            query($teamId: String!) {
              team(id: $teamId) { activeCycle { id } }
            }
          '# { teamId: $team.id })
          if $data.team.activeCycle == null {
            exit-error "No active cycle for team"
          }
          $data.team.activeCycle.id
        } else {
          let data = (linear-query r#'
            query { cycles(first: 100) { nodes { id name } } }
          '#)
          let found = $data.cycles.nodes | where name == $cycle | first
          if $found == null { exit-error $"Cycle '($cycle)' not found" }
          $found.id
        }
        { cycle: { id: { eq: $cycle_id } } }
      } else { {} })
  )

  # Include relations in query if filtering by blocked/blocking
  let query = if $blocked or $blocking {
    r#'
    query($filter: IssueFilter, $limit: Int!) {
      issues(filter: $filter, first: $limit, orderBy: updatedAt) {
        nodes {
          identifier title priority
          state { name }
          labels { nodes { name } }
          assignee { name }
          parent { identifier }
          relations(first: 50) {
            nodes { type }
          }
        }
      }
    }
    '#
  } else {
    r#'
    query($filter: IssueFilter, $limit: Int!) {
      issues(filter: $filter, first: $limit, orderBy: updatedAt) {
        nodes {
          identifier title priority
          state { name }
          labels { nodes { name } }
          assignee { name }
          parent { identifier }
        }
      }
    }
    '#
  }

  let data = (linear-query $query { filter: $filter, limit: $limit })

  let issues = $data.issues.nodes
    | where { |i|
        let dominated = not $blocked or ($i.relations?.nodes? | default [] | where type == "blocked_by" | length) > 0
        let doms = not $blocking or ($i.relations?.nodes? | default [] | where type == "blocks" | length) > 0
        $dominated and $doms
      }

  let result = $issues | each { |i| {
    id: $i.identifier
    status: $i.state.name
    priority: $i.priority
    title: $i.title
    labels: ($i.labels.nodes | get name)
    assignee: ($i.assignee?.name? | default null)
    epic: ($i.parent?.identifier? | default null)
  }}

  if $json {
    $result | to json
  } else {
    $result | each { |i| {
      ID: $i.id
      Status: $i.status
      Priority: $i.priority
      Title: ($i.title | truncate 45)
      Labels: ($i.labels | str join ", ")
      Assignee: ($i.assignee | default "-")
      Epic: ($i.epic | default "-")
    }}
  }
}

# Show issue details
export def "main show" [
  id: string              # Issue ID (e.g., DIG-44)
  --relations (-r)        # Include blocking/blocked-by relations
  --json (-j)             # Output as JSON
] {
  let query = if $relations {
    r#'
    query($id: String!) {
      issue(id: $id) {
        identifier title description url
        state { name }
        priority
        labels { nodes { name } }
        assignee { name }
        parent { identifier title }
        children { nodes { identifier title state { name } } }
        project { name }
        relations(first: 50) {
          nodes {
            type
            relatedIssue { identifier title state { name } }
          }
        }
      }
    }
    '#
  } else {
    r#'
    query($id: String!) {
      issue(id: $id) {
        identifier title description url
        state { name }
        priority
        labels { nodes { name } }
        assignee { name }
        parent { identifier title }
        children { nodes { identifier title state { name } } }
        project { name }
      }
    }
    '#
  }

  let data = (linear-query $query { id: $id })

  let i = $data.issue
  if $i == null { exit-error $"Issue '($id)' not found" }

  if $json {
    return ({
      id: $i.identifier
      title: $i.title
      description: $i.description
      url: $i.url
      status: $i.state.name
      priority: $i.priority
      labels: ($i.labels.nodes | get name)
      assignee: ($i.assignee?.name? | default null)
      epic: (if $i.parent != null { { id: $i.parent.identifier, title: $i.parent.title } } else { null })
      project: ($i.project?.name? | default null)
      children: ($i.children.nodes | each { |c| { id: $c.identifier, title: $c.title, status: $c.state.name } })
      relations: (if $relations { $i.relations?.nodes? | default [] | each { |r| { type: $r.type, issue: { id: $r.relatedIssue.identifier, title: $r.relatedIssue.title, status: $r.relatedIssue.state.name } } } } else { null })
    } | to json)
  }

  print $"(ansi green_bold)($i.identifier)(ansi reset) - ($i.title)"
  print $"(ansi cyan)Status:(ansi reset) ($i.state.name)"
  print $"(ansi cyan)URL:(ansi reset) ($i.url)"
  if $i.parent != null { print $"(ansi cyan)Epic:(ansi reset) ($i.parent.identifier) - ($i.parent.title)" }
  if $i.assignee != null { print $"(ansi cyan)Assignee:(ansi reset) ($i.assignee.name)" }
  if ($i.labels.nodes | length) > 0 { print $"(ansi cyan)Labels:(ansi reset) ($i.labels.nodes | get name | str join ', ')" }
  if $i.description != null and $i.description != "" { print $"\n(ansi cyan)Description:(ansi reset)\n($i.description)" }
  if ($i.children.nodes | length) > 0 {
    print $"\n(ansi cyan)Sub-issues:(ansi reset)"
    $i.children.nodes | each { |c| { ID: $c.identifier, Status: $c.state.name, Title: $c.title } } | print
  }

  if $relations and ($i.relations?.nodes? | default [] | length) > 0 {
    let rels = $i.relations.nodes
    let blocks = $rels | where type == "blocks"
    let blocked_by = $rels | where type == "blocked_by"

    if ($blocked_by | length) > 0 {
      print $"\n(ansi red_bold)Blocked by:(ansi reset)"
      $blocked_by | each { |r| {
        ID: $r.relatedIssue.identifier
        Status: $r.relatedIssue.state.name
        Title: $r.relatedIssue.title
      }} | print
    }

    if ($blocks | length) > 0 {
      print $"\n(ansi yellow_bold)Blocks:(ansi reset)"
      $blocks | each { |r| {
        ID: $r.relatedIssue.identifier
        Status: $r.relatedIssue.state.name
        Title: $r.relatedIssue.title
      }} | print
    }
  }
}

# Show issue comments
export def "main comments" [
  id: string  # Issue ID
] {
  let data = (linear-query r#'
    query($id: String!) {
      issue(id: $id) {
        identifier title
        comments { nodes { body createdAt user { name } } }
      }
    }
  '# { id: $id })

  let i = $data.issue
  if $i == null { exit-error $"Issue '($id)' not found" }

  print $"(ansi green_bold)($i.identifier)(ansi reset) - ($i.title)\n"

  let comments = $i.comments.nodes
  if ($comments | length) == 0 { print "No comments"; return }

  for c in $comments {
    let date = ($c.createdAt | into datetime | format date "%Y-%m-%d %H:%M")
    print $"(ansi cyan)($c.user?.name? | default 'Unknown')(ansi reset) - ($date)\n($c.body)\n"
  }
  print $"($comments | length) comments"
}

# Add comment to issue
export def "main comment" [
  id: string    # Issue ID
  body: string  # Comment text (markdown)
] {
  let uuid = (get-issue-uuid $id)
  let data = (linear-query r#'
    mutation($issueId: String!, $body: String!) {
      commentCreate(input: { issueId: $issueId, body: $body }) { success }
    }
  '# { issueId: $uuid, body: $body })

  if $data.commentCreate.success { print $"Comment added to ($id)" } else { exit-error "Failed to add comment" }
}

# Update issue status
export def "main status" [
  id: string      # Issue ID
  status: string  # Status: backlog, todo, inprogress, done, canceled
] {
  let uuid = (get-issue-uuid $id)
  let states = (linear-query r#'{ workflowStates(first: 50) { nodes { id name } } }'#)
  let state = $states.workflowStates.nodes | where name == (map-status $status) | first
  if $state == null { exit-error $"Unknown status '($status)'. Use: backlog, todo, inprogress, done, canceled" }

  let data = (linear-query r#'
    mutation($id: String!, $stateId: String!) {
      issueUpdate(id: $id, input: { stateId: $stateId }) {
        success
        issue { identifier state { name } }
      }
    }
  '# { id: $uuid, stateId: $state.id })

  if $data.issueUpdate.success { print $"($data.issueUpdate.issue.identifier) → ($data.issueUpdate.issue.state.name)" } else { exit-error "Failed to update status" }
}

# Create new issue
export def "main create" [
  title: string              # Issue title
  --type (-t): string        # Type: feature, bug, refactor, docs, chore
  --epic (-e): string        # Parent epic ID
  --label (-l): string       # Additional label
  --description (-d): string # Issue description
  --team (-T): string        # Team name (required if multiple teams)
] {
  let team_rec = (get-team $team)
  let type_map = { feature: "Feature", bug: "Bug", refactor: "refactor", docs: "docs", chore: "Chore" }

  let labels = ([]
    | append (if $type != null { $type_map | get -o $type | default $type } else { null })
    | append (if $label != null { $label } else { null })
    | compact
  )

  let input = ({ teamId: $team_rec.id, title: $title }
    | merge (if ($labels | length) > 0 { { labelIds: (resolve-labels $labels) } } else { {} })
    | merge (if $epic != null { { parentId: (get-issue-uuid $epic) } } else { {} })
    | merge (if $description != null { { description: $description } } else { {} })
  )

  let data = (linear-query r#'
    mutation($input: IssueCreateInput!) {
      issueCreate(input: $input) {
        success
        issue { identifier title url }
      }
    }
  '# { input: $input })

  if $data.issueCreate.success {
    let i = $data.issueCreate.issue
    print $"Created: ($i.identifier) - ($i.title)\nURL: ($i.url)"
  } else { exit-error "Failed to create issue" }
}

# Edit issue fields
export def "main edit" [
  id: string                    # Issue ID
  --title (-t): string          # New title
  --description (-d): string    # New description
  --parent (-p): string         # Parent issue (epic)
  --labels (-l): string         # Labels (comma-separated)
  --assignee (-a): string       # Assignee name or "me"
  --priority: int               # Priority: 0=none, 1=urgent, 2=high, 3=medium, 4=low
] {
  let uuid = (get-issue-uuid $id)

  let input = ({}
    | merge (if $title != null { { title: $title } } else { {} })
    | merge (if $description != null { { description: $description } } else { {} })
    | merge (if $parent != null { { parentId: (get-issue-uuid $parent) } } else { {} })
    | merge (if $labels != null { { labelIds: (resolve-labels ($labels | split row "," | each { str trim })) } } else { {} })
    | merge (if $assignee != null { { assigneeId: (resolve-user $assignee).id } } else { {} })
    | merge (if $priority != null { { priority: $priority } } else { {} })
  )

  if ($input | columns | length) == 0 {
    print "No changes specified. Use --title, --description, --parent, --labels, --assignee, or --priority"
    return
  }

  let data = (linear-query r#'
    mutation($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) {
        success
        issue { identifier title }
      }
    }
  '# { id: $uuid, input: $input })

  if $data.issueUpdate.success { print $"Updated ($data.issueUpdate.issue.identifier): ($input | columns | str join ', ')" } else { exit-error "Failed to update issue" }
}

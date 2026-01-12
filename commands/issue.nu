# Issue commands

use ../lib/api.nu [exit-error, linear-query, truncate, map-status, edit-in-editor, parse-markdown-doc, read-content-file, display-kv, display-section, format-date]
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
  let filter = {}
  
  let filter = if $status != null {
    $filter | merge { state: { name: { eq: (map-status $status) } } }
  } else { $filter }

  let filter = if $label != null {
    $filter | merge { labels: { name: { eq: $label } } }
  } else { $filter }

  let filter = if $epic != null {
    $filter | merge { parent: { id: { eq: (get-issue-uuid $epic) } } }
  } else { $filter }

  let filter = if $project != null {
    $filter | merge { project: { name: { eq: $project } } }
  } else { $filter }

  let filter = if $assignee != null {
    let user = (resolve-user $assignee)
    $filter | merge { assignee: { id: { eq: $user.id } } }
  } else { $filter }

  let filter = if $cycle != null {
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
    $filter | merge { cycle: { id: { eq: $cycle_id } } }
  } else { $filter }

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
  id?: string             # Issue ID (e.g., DIG-44)
  --relations (-r)        # Include blocking/blocked-by relations
  --json (-j)             # Output as JSON
] {
  let id = if $id == null {
    let val = (input "Issue ID/Title: ")
    if ($val | is-empty) { exit-error "Issue ID is required" }
    $val
  } else { $id }

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

  let uuid = (get-issue-uuid $id)
  let data = (linear-query $query { id: $uuid })

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
  display-kv "Status" $i.state.name
  display-kv "URL" $i.url
  if $i.parent != null { display-kv "Epic" $"($i.parent.identifier) - ($i.parent.title)" }
  if $i.assignee != null { display-kv "Assignee" $i.assignee.name }
  if ($i.labels.nodes | length) > 0 { display-kv "Labels" ($i.labels.nodes | get name | str join ", ") }
  if $i.description != null and $i.description != "" { 
    print ""
    display-section "Description"
    print $i.description 
  }
  
  if ($i.children.nodes | length) > 0 {
    print ""
    display-section "Sub-issues"
    $i.children.nodes | each { |c| { ID: $c.identifier, Status: $c.state.name, Title: $c.title } } | print
  }

  if $relations and ($i.relations?.nodes? | default [] | length) > 0 {
    let rels = $i.relations.nodes
    let blocks = $rels | where type == "blocks"
    let blocked_by = $rels | where type == "blocked_by"

    if ($blocked_by | length) > 0 {
      print ""
      display-section "Blocked by"
      $blocked_by | each { |r| {
        ID: $r.relatedIssue.identifier
        Status: $r.relatedIssue.state.name
        Title: $r.relatedIssue.title
      }} | print
    }

    if ($blocks | length) > 0 {
      print ""
      display-section "Blocks"
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
  id?: string  # Issue ID
] {
  let id = if $id == null {
    let val = (input "Issue ID/Title: ")
    if ($val | is-empty) { exit-error "Issue ID is required" }
    $val
  } else { $id }

  let uuid = (get-issue-uuid $id)
  let data = (linear-query r#'
    query($id: String!) {
      issue(id: $id) {
        identifier title
        comments { nodes { body createdAt user { name } } }
      }
    }
  '# { id: $uuid })

  let i = $data.issue
  if $i == null { exit-error $"Issue '($id)' not found" }

  print $"(ansi green_bold)($i.identifier)(ansi reset) - ($i.title)\n"

  let comments = $i.comments.nodes
  if ($comments | length) == 0 { print "No comments"; return }

  for c in $comments {
    let date = ($c.createdAt | format-date "%Y-%m-%d %H:%M")
    print $"(ansi cyan)($c.user?.name? | default 'Unknown')(ansi reset) - ($date)\n($c.body)\n"
  }
  print $"($comments | length) comments"
}

# Add comment to issue
export def "main comment" [
  id?: string                    # Issue ID
  body?: string                 # Comment text (markdown)
  --body-file (-f): string      # Read comment from file (use "-" for stdin)
] {
  let id = if $id == null {
    let val = (input "Issue ID/Title: ")
    if ($val | is-empty) { exit-error "Issue ID is required" }
    $val
  } else { $id }

  # Validate: need exactly one of body or body-file
  if $body != null and $body_file != null {
    exit-error "Cannot use both body argument and --body-file"
  }
  
  let comment_body = if $body_file != null {
    read-content-file $body_file
  } else if $body != null {
    $body
  } else {
    let val = (input "Comment: ")
    if ($val | is-empty) { exit-error "Comment body is required" }
    $val
  }

  let uuid = (get-issue-uuid $id)
  let data = (linear-query r#'
    mutation($issueId: String!, $body: String!) {
      commentCreate(input: { issueId: $issueId, body: $body }) { success }
    }
  '# { issueId: $uuid, body: $comment_body })

  if $data.commentCreate.success { print $"Comment added to ($id)" } else { exit-error "Failed to add comment" }
}

# Update issue status
export def "main status" [
  id?: string      # Issue ID
  status?: string  # Status: backlog, todo, inprogress, done, canceled
] {
  let id = if $id == null {
    let val = (input "Issue ID/Title: ")
    if ($val | is-empty) { exit-error "Issue ID is required" }
    $val
  } else { $id }

  let uuid = (get-issue-uuid $id)
  let states = (linear-query r#'{ workflowStates(first: 50) { nodes { id name } } }'#)
  
  let state_id = if $status != null {
    let state = $states.workflowStates.nodes | where name == (map-status $status) | first
    if $state == null { exit-error $"Unknown status '($status)'. Use: backlog, todo, inprogress, done, canceled" }
    $state.id
  } else {
    let options = ($states.workflowStates.nodes | get name)
    let choice = ($options | input list "Select Status:")
    if $choice == null { exit-error "No status selected" }
    ($states.workflowStates.nodes | where name == $choice | first).id
  }

  let data = (linear-query r#'
    mutation($id: String!, $stateId: String!) {
      issueUpdate(id: $id, input: { stateId: $stateId }) {
        success
        issue { identifier state { name } }
      }
    }
  '# { id: $uuid, stateId: $state_id })

  if $data.issueUpdate.success { print $"($data.issueUpdate.issue.identifier) → ($data.issueUpdate.issue.state.name)" } else { exit-error "Failed to update status" }
}

# Create new issue
export def "main create" [
  title?: string             # Issue title
  --type (-t): string        # Type: feature, bug, refactor, docs, chore
  --epic (-e): string        # Parent epic ID
  --label (-l): string       # Additional label
  --description (-d): string # Issue description
  --description-file (-D): string # Read description from file (use "-" for stdin)
  --team (-T): string        # Team name (required if multiple teams)
] {
  let interactive = ($title == null)

  let title = if $interactive {
    print "(ansi cyan)Interactive Issue Creation(ansi reset)"
    let t = (input "Title: ")
    if ($t | is-empty) { exit-error "Title is required" }
    $t
  } else { $title }

  # Validate mutual exclusivity
  if $description != null and $description_file != null {
    exit-error "Cannot use both --description and --description-file"
  }

  # Resolve description from file if provided or interactive
  let desc = if $description_file != null {
    read-content-file $description_file
  } else if $description != null {
    $description
  } else if $interactive {
    input "Description (optional): "
  } else {
    null
  }

  let team_rec = (get-team $team)
  let type_map = { feature: "Feature", bug: "Bug", refactor: "refactor", docs: "docs", chore: "Chore" }
  
  let type_val = if $interactive and $type == null {
    let types = ["feature", "bug", "refactor", "docs", "chore"]
    $types | input list "Type (optional): "
  } else { $type }

  let labels = ([]
    | append (if $type_val != null { $type_map | get -o $type_val | default $type_val } else { null })
    | append (if $label != null { $label } else { null })
    | compact
  )

  let input = ({ teamId: $team_rec.id, title: $title }
    | merge (if ($labels | length) > 0 { { labelIds: (resolve-labels $labels) } } else { {} })
    | merge (if $epic != null { { parentId: (get-issue-uuid $epic) } } else { {} })
    | merge (if $desc != null and $desc != "" { { description: $desc } } else { {} })
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
  id?: string                   # Issue ID
  --title (-t): string          # New title
  --description (-d): string    # New description
  --description-file (-D): string # Read description from file (use "-" for stdin)
  --epic (-e): string           # Parent issue (epic)
  --parent (-p): string         # Alias for --epic
  --labels (-l): string         # Labels (comma-separated)
  --assignee (-a): string       # Assignee name or "me"
  --priority: int               # Priority: 0=none, 1=urgent, 2=high, 3=medium, 4=low
] {
  let id = if $id == null {
    let val = (input "Issue ID/Title: ")
    if ($val | is-empty) { exit-error "Issue ID is required" }
    $val
  } else { $id }

  # Validate mutual exclusivity
  if $description != null and $description_file != null {
    exit-error "Cannot use both --description and --description-file"
  }

  # Handle epic/parent alias
  let parent_val = if $epic != null { $epic } else { $parent }

  # Resolve description from file if provided
  let desc = if $description_file != null {
    read-content-file $description_file
  } else {
    $description
  }

  let uuid = (get-issue-uuid $id)
  let has_flags = $title != null or $desc != null or $parent_val != null or $labels != null or $assignee != null or $priority != null

  # If no flags, open in editor
  if not $has_flags {
    # Fetch current issue content
    let data = (linear-query r#'
      query($id: String!) {
        issue(id: $id) { identifier title description }
      }
    '# { id: $id })

    let issue = $data.issue
    if $issue == null { exit-error $"Issue '($id)' not found" }

    # Format as markdown
    let content = $"# ($issue.title)\n\n($issue.description | default '')"

    let edited = (edit-in-editor $content)
    if $edited == null {
      print "No changes made"
      return
    }

    let parsed = (parse-markdown-doc $edited)

    let input = { title: $parsed.title, description: $parsed.body }
    let update = (linear-query r#'
      mutation($id: String!, $input: IssueUpdateInput!) {
        issueUpdate(id: $id, input: $input) {
          success
          issue { identifier title }
        }
      }
    '# { id: $uuid, input: $input })

    if $update.issueUpdate.success {
      print $"Updated ($update.issueUpdate.issue.identifier): ($update.issueUpdate.issue.title)"
    } else {
      exit-error "Failed to update issue"
    }
    return
  }

  # Flag-based update
  let input = ({} 
    | merge (if $title != null { { title: $title } } else { {} })
    | merge (if $desc != null { { description: $desc } } else { {} })
    | merge (if $parent_val != null { { parentId: (get-issue-uuid $parent_val) } } else { {} })
    | merge (if $labels != null { { labelIds: (resolve-labels ($labels | split row "," | each { str trim })) } } else { {} })
    | merge (if $assignee != null { { assigneeId: (resolve-user $assignee).id } } else { {} })
    | merge (if $priority != null { { priority: $priority } } else { {} })
  )

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

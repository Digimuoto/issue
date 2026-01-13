# Issue commands

use ../lib/api.nu [exit-error, linear-query, map-status, edit-in-editor, parse-markdown-doc, read-content-file, compact-record, format-date]
use ../lib/resolvers.nu [get-team, resolve-user, get-issue-uuid, resolve-labels, resolve-cycle]
use ../lib/ui.nu [prompt, prompt-select, render-issue, render-comments, truncate, apply-view]

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
  --cols: string           # Columns to show (e.g. ID,Title)
  --rows: string           # Rows to show (e.g. 1-5,10)
  --sort: string           # Column to sort by
] {
  let filter = {
    state: (if $status != null { { name: { eq: (map-status $status) } } } else { null })
    labels: (if $label != null { { name: { eq: $label } } } else { null })
    parent: (if $epic != null { { id: { eq: (get-issue-uuid $epic) } } } else { null })
    project: (if $project != null { { name: { eq: $project } } } else { null })
    assignee: (if $assignee != null { { id: { eq: (resolve-user $assignee).id } } } else { null })
    cycle: (if $cycle != null { { id: { eq: (resolve-cycle $cycle) } } } else { null })
  } | compact-record

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
    | apply-view --cols $cols --rows $rows --sort $sort
  }
}

# Show issue details
export def "main show" [
  id?: string             # Issue ID (e.g., DIG-44)
  --relations (-r)        # Include blocking/blocked-by relations
  --json (-j)             # Output as JSON
] {
  let id = if $id == null { prompt "Issue ID/Title: " --required } else { $id }

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

  render-issue $i
}

# Show issue comments
export def "main comments" [
  id?: string  # Issue ID
] {
  let id = if $id == null { prompt "Issue ID/Title: " --required } else { $id }

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
  render-comments $i.comments.nodes
}

# Add comment to issue
export def "main comment" [
  id?: string                   # Issue ID
  body?: string                 # Comment text (markdown)
  --body-file (-f): string      # Read comment from file (use "-" for stdin)
] {
  let id = if $id == null { prompt "Issue ID/Title: " --required } else { $id }

  # Validate: need exactly one of body or body-file
  if $body != null and $body_file != null {
    exit-error "Cannot use both body argument and --body-file"
  }
  
  let comment_body = if $body_file != null {
    read-content-file $body_file
  } else if $body != null {
    $body
  } else {
    prompt "Comment: " --required
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
  let id = if $id == null { prompt "Issue ID/Title: " --required } else { $id }

  let uuid = (get-issue-uuid $id)
  let states = (linear-query r#'{ workflowStates(first: 50) { nodes { id name } } }'#)
  
  let state_id = if $status != null {
    let state = $states.workflowStates.nodes | where name == (map-status $status) | first
    if $state == null { exit-error $"Unknown status '($status)'. Use: backlog, todo, inprogress, done, canceled" }
    $state.id
  } else {
    let options = ($states.workflowStates.nodes | get name)
    let choice = (prompt-select "Select Status:" $options)
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
    prompt "Title: " --required
  } else { $title }

  if $description != null and $description_file != null {
    exit-error "Cannot use both --description and --description-file"
  }

  let desc = if $description_file != null {
    read-content-file $description_file
  } else if $description != null {
    $description
  } else if $interactive {
    prompt "Description (optional): "
  } else {
    null
  }

  let team_rec = (get-team $team)
  let type_map = { feature: "Feature", bug: "Bug", refactor: "refactor", docs: "docs", chore: "Chore" }
  
  let type_val = if $interactive and $type == null {
    let types = ["feature", "bug", "refactor", "docs", "chore"]
    prompt-select "Type (optional): " $types
  } else { $type }

  let labels = ([]
    | append (if $type_val != null { $type_map | get -o $type_val | default $type_val } else { null })
    | append (if $label != null { $label } else { null })
    | compact
  )

  let input = {
    teamId: $team_rec.id
    title: $title
    description: (if $desc != "" { $desc } else { null })
    labelIds: (if ($labels | length) > 0 { (resolve-labels $labels) } else { null })
    parentId: (if $epic != null { (get-issue-uuid $epic) } else { null })
  } | compact-record

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
  let id = if $id == null { prompt "Issue ID/Title: " --required } else { $id }

  if $description != null and $description_file != null {
    exit-error "Cannot use both --description and --description-file"
  }

  let parent_val = if $epic != null { $epic } else { $parent }

  let desc = if $description_file != null {
    read-content-file $description_file
  } else {
    $description
  }

  let uuid = (get-issue-uuid $id)
  let has_flags = $title != null or $desc != null or $parent_val != null or $labels != null or $assignee != null or $priority != null

  # If no flags, open in editor
  if not $has_flags {
    let data = (linear-query r#'
      query($id: String!) {
        issue(id: $id) { identifier title description }
      }
    '# { id: $uuid })

    let issue = $data.issue
    if $issue == null { exit-error $"Issue '($id)' not found" }

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
  let input = {
    title: $title
    description: $desc
    parentId: (if $parent_val != null { (get-issue-uuid $parent_val) } else { null })
    labelIds: (if $labels != null { (resolve-labels ($labels | split row "," | each { str trim })) } else { null })
    assigneeId: (if $assignee != null { (resolve-user $assignee).id } else { null })
    priority: $priority
  } | compact-record

  let data = (linear-query r#'
    mutation($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) {
        success
        issue { identifier title }
      }
    }
  '# { id: $uuid, input: $input })

  if $data.issueUpdate.success { print $"Updated ($data.issueUpdate.issue.identifier): ($input | columns | str join ", ")" } else { exit-error "Failed to update issue" }
}
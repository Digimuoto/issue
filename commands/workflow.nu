# Workflow commands: start, current, done

use ../lib/api.nu [exit-error, linear-query, map-status]
use ../lib/resolvers.nu [get-issue-uuid, get-viewer]
use ../lib/state.nu [get-current, get-current-issues, add-current, remove-current, clear-current, slugify]

# Start working on an issue
export def "main start" [
  id: string  # Issue ID (e.g., DIG-123)
] {
  # Fetch issue details
  let data = (linear-query r#'
    query($id: String!) {
      issue(id: $id) {
        id identifier title
        state { name type }
        assignee { id }
      }
    }
  '# { id: $id })

  let issue = $data.issue
  if $issue == null { exit-error $"Issue '($id)' not found" }

  # Get "In Progress" state
  let states = (linear-query r#'{ workflowStates(first: 50) { nodes { id name } } }'#)
  let in_progress = $states.workflowStates.nodes | where name == "In Progress" | first
  if $in_progress == null { exit-error "Could not find 'In Progress' state" }

  # Update issue: set status and assign to self if unassigned
  let viewer = (get-viewer)
  let input = { stateId: $in_progress.id }
    | merge (if $issue.assignee == null { { assigneeId: $viewer.id } } else { {} })

  let update = (linear-query r#'
    mutation($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) {
        success
        issue { identifier state { name } assignee { name } }
      }
    }
  '# { id: $issue.id, input: $input })

  if not $update.issueUpdate.success { exit-error "Failed to update issue" }

  # Create git branch
  let branch = $"($issue.identifier | str downcase)-(slugify $issue.title)"
  let branch_result = do { git checkout -b $branch } | complete

  if $branch_result.exit_code != 0 {
    # Branch might already exist, try to check it out
    let checkout_result = do { git checkout $branch } | complete
    if $checkout_result.exit_code != 0 {
      print $"(ansi yellow)Warning: Could not create/checkout branch '($branch)'(ansi reset)"
    }
  }

  # Add to current issues list
  add-current $issue.identifier

  # Print confirmation
  let updated = $update.issueUpdate.issue
  print $"(ansi green_bold)Started:(ansi reset) ($updated.identifier) - ($issue.title)"
  print $"(ansi cyan)Status:(ansi reset) ($updated.state.name)"
  print $"(ansi cyan)Assignee:(ansi reset) ($updated.assignee.name)"
  print $"(ansi cyan)Branch:(ansi reset) ($branch)"
}

# Show current issue context
export def "main current" [
  id?: string     # Specific issue ID to show (optional)
  --pr (-p)       # Only show linked PR status
  --json (-j)     # Output as JSON
] {
  let all_ids = (get-current-issues)
  if ($all_ids | length) == 0 {
    exit-error "No current issues. Use 'issue start <id>' to begin."
  }

  # If specific ID given, validate it's in list
  let target_ids = if $id != null {
    if not ($id in $all_ids) {
      exit-error $"Issue '($id)' is not in current list. Current: ($all_ids | str join ', ')"
    }
    [$id]
  } else {
    $all_ids
  }

  # Query each issue individually (Linear API doesn't support identifier filter)
  let issues = $target_ids | each { |id|
    let data = (linear-query r#'
      query($id: String!) {
        issue(id: $id) {
          identifier title url
          state { name }
          assignee { name }
          attachments(first: 20) {
            nodes {
              title subtitle url sourceType
            }
          }
        }
      }
    '# { id: $id })
    $data.issue
  } | compact

  if $json {
    return ($issues | each { |issue|
      let prs = $issue.attachments.nodes | where { |a| $a.sourceType? == "github" or ($a.url | str contains "github.com") }
      {
        id: $issue.identifier
        title: $issue.title
        url: $issue.url
        status: $issue.state.name
        assignee: ($issue.assignee?.name? | default null)
        prs: ($prs | each { |p| { title: $p.title, status: ($p.subtitle | default null), url: $p.url } })
      }
    } | to json)
  }

  if $pr {
    # Only show PRs for all issues
    for issue in $issues {
      let prs = $issue.attachments.nodes | where { |a| $a.sourceType? == "github" or ($a.url | str contains "github.com") }
      if ($prs | length) > 0 {
        print $"(ansi cyan)PRs for ($issue.identifier):(ansi reset)"
        $prs | each { |p| {
          Title: $p.title
          Status: ($p.subtitle | default "-")
          URL: $p.url
        }} | print
      }
    }
    if ($issues | all { |i| ($i.attachments.nodes | where { |a| $a.sourceType? == "github" or ($a.url | str contains "github.com") } | length) == 0 }) {
      print "No linked PRs"
    }
  } else {
    # Show all current issues
    if ($all_ids | length) > 1 {
      print $"(ansi cyan)Current issues:(ansi reset) ($all_ids | str join ', ')\n"
    }

    for issue in $issues {
      print $"(ansi green_bold)($issue.identifier)(ansi reset) - ($issue.title)"
      print $"(ansi cyan)Status:(ansi reset) ($issue.state.name)"
      print $"(ansi cyan)Assignee:(ansi reset) ($issue.assignee?.name? | default '-')"
      print $"(ansi cyan)URL:(ansi reset) ($issue.url)"

      let prs = $issue.attachments.nodes | where { |a| $a.sourceType? == "github" or ($a.url | str contains "github.com") }
      if ($prs | length) > 0 {
        print $"(ansi cyan)PRs:(ansi reset)"
        $prs | each { |p| {
          Title: $p.title
          Status: ($p.subtitle | default "-")
          URL: $p.url
        }} | print
      }
      print ""
    }
  }
}

# Mark issue as done
export def "main done" [
  id?: string     # Issue ID (uses current if not specified)
  --force (-f)    # Skip warnings and mark done anyway
] {
  let issue_id = if $id != null { $id } else { get-current }
  if $issue_id == null { exit-error "No issue specified and no current issue set." }

  # Fetch issue with relations and attachments
  let data = (linear-query r#'
    query($id: String!) {
      issue(id: $id) {
        id identifier title
        state { name }
        relations(first: 50) {
          nodes {
            type
            relatedIssue { identifier title state { name type } }
          }
        }
        attachments(first: 20) {
          nodes {
            title subtitle url sourceType
          }
        }
      }
    }
  '# { id: $issue_id })

  let issue = $data.issue
  if $issue == null { exit-error $"Issue '($issue_id)' not found" }

  # Check blockers
  let blockers = $issue.relations.nodes
    | where type == "blocked_by"
    | where { |r| $r.relatedIssue.state.type != "completed" and $r.relatedIssue.state.type != "canceled" }

  # Check PRs
  let prs = $issue.attachments.nodes | where { |a| $a.sourceType? == "github" or ($a.url | str contains "github.com") }
  let open_prs = $prs | where { |p|
    let status = ($p.subtitle | default "" | str downcase)
    $status != "merged" and $status != "closed"
  }

  let has_warnings = ($blockers | length) > 0 or ($open_prs | length) > 0

  if $has_warnings and not $force {
    if ($blockers | length) > 0 {
      print $"(ansi red_bold)Blocked by unresolved issues:(ansi reset)"
      $blockers | each { |b| print $"  - ($b.relatedIssue.identifier): ($b.relatedIssue.title) [($b.relatedIssue.state.name)]" }
    }
    if ($open_prs | length) > 0 {
      print $"(ansi yellow_bold)Open PRs:(ansi reset)"
      $open_prs | each { |p| print $"  - ($p.title) [($p.subtitle | default 'Open')]" }
    }
    print $"\nUse --force to mark done anyway."
    return
  }

  # Get "Done" state
  let states = (linear-query r#'{ workflowStates(first: 50) { nodes { id name } } }'#)
  let done_state = $states.workflowStates.nodes | where name == "Done" | first
  if $done_state == null { exit-error "Could not find 'Done' state" }

  # Update issue
  let update = (linear-query r#'
    mutation($id: String!, $stateId: String!) {
      issueUpdate(id: $id, input: { stateId: $stateId }) {
        success
        issue { identifier state { name } }
      }
    }
  '# { id: $issue.id, stateId: $done_state.id })

  if not $update.issueUpdate.success { exit-error "Failed to update issue" }

  # Remove from current issues list
  remove-current $issue.identifier

  print $"(ansi green_bold)Done:(ansi reset) ($issue.identifier) - ($issue.title)"
}

# Show PRs linked to current issues
export def "main pr" [
  --json (-j)     # Output as JSON
] {
  let issue_ids = (get-current-issues)
  if ($issue_ids | length) == 0 {
    exit-error "No current issues. Use 'issue start <id>' to begin."
  }

  # Query each issue individually (Linear API doesn't support identifier filter)
  let issues = $issue_ids | each { |id|
    let data = (linear-query r#'
      query($id: String!) {
        issue(id: $id) {
          identifier title
          attachments(first: 20) {
            nodes {
              title subtitle url sourceType
            }
          }
        }
      }
    '# { id: $id })
    $data.issue
  } | compact

  let results = $issues | each { |issue|
    let prs = $issue.attachments.nodes
      | where { |a| $a.sourceType? == "github" or ($a.url | str contains "github.com") }

    $prs | each { |pr|
      {
        issue: $issue.identifier
        title: $pr.title
        status: ($pr.subtitle | default "Open")
        url: $pr.url
      }
    }
  } | flatten

  if $json {
    return ($results | to json)
  }

  if ($results | length) == 0 {
    print "No linked PRs found"
  } else {
    $results | each { |r| {
      Issue: $r.issue
      PR: $r.title
      Status: $r.status
      URL: $r.url
    }}
  }
}

# Workflow commands: start, scope, done

use ../lib/api.nu [exit-error, linear-query, map-status]
use ../lib/resolvers.nu [get-issue-uuid, get-viewer]
use ../lib/state.nu [get-current, get-current-issues, add-current, remove-current, clear-current, set-cached-prs, slugify]

# Start working on issue(s)
export def "main start" [
  ids: string  # Issue ID(s), comma-separated (e.g., DIG-123 or DIG-1,DIG-2,DIG-3)
] {
  let issue_ids = $ids | split row "," | each { str trim }

  # Get workflow states once
  let states = (linear-query r#'{ workflowStates(first: 50) { nodes { id name } } }'#)
  let in_progress = $states.workflowStates.nodes | where name == "In Progress" | first
  if $in_progress == null { exit-error "Could not find 'In Progress' state" }

  let viewer = (get-viewer)

  for id in $issue_ids {
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
    if $issue == null {
      print $"(ansi yellow)Warning: Issue '($id)' not found, skipping(ansi reset)"
      continue
    }

    # Update issue: set status and assign to self if unassigned
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

    if not $update.issueUpdate.success {
      print $"(ansi yellow)Warning: Failed to update '($id)', skipping(ansi reset)"
      continue
    }

    # Add to scope
    add-current $issue.identifier

    let updated = $update.issueUpdate.issue
    print $"(ansi green_bold)Started:(ansi reset) ($updated.identifier) - ($issue.title)"
  }

  # Create git branch for first issue only
  if ($issue_ids | length) == 1 {
    let first_id = $issue_ids.0
    let data = (linear-query r#'query($id: String!) { issue(id: $id) { identifier title } }'# { id: $first_id })
    if $data.issue != null {
      let branch = $"($data.issue.identifier | str downcase)-(slugify $data.issue.title)"
      let branch_result = do { git checkout -b $branch } | complete
      if $branch_result.exit_code != 0 {
        let checkout_result = do { git checkout $branch } | complete
        if $checkout_result.exit_code != 0 {
          print $"(ansi yellow)Warning: Could not create/checkout branch '($branch)'(ansi reset)"
        }
      }
      print $"(ansi cyan)Branch:(ansi reset) ($branch)"
    }
  }
}

# Manage issue scope for this repo
export def "main scope" [
  --add (-a): string     # Add issue(s) to scope (comma-separated)
  --remove (-r): string  # Remove issue(s) from scope (comma-separated)
  --clear (-c)           # Clear all issues from scope
  --json (-j)            # Output as JSON
] {
  # Handle modifications first
  if $clear {
    clear-current
    print "Scope cleared"
    return
  }

  if $add != null {
    let ids = $add | split row "," | each { str trim }
    for id in $ids {
      # Validate issue exists
      let data = (linear-query r#'query($id: String!) { issue(id: $id) { identifier title } }'# { id: $id })
      if $data.issue == null {
        print $"(ansi yellow)Warning: Issue '($id)' not found, skipping(ansi reset)"
        continue
      }
      add-current $data.issue.identifier
      print $"(ansi green)Added:(ansi reset) ($data.issue.identifier) - ($data.issue.title)"
    }
    return
  }

  if $remove != null {
    let ids = $remove | split row "," | each { str trim }
    for id in $ids {
      remove-current $id
      print $"(ansi yellow)Removed:(ansi reset) ($id)"
    }
    return
  }

  # Show current scope
  let all_ids = (get-current-issues)
  if ($all_ids | length) == 0 {
    if $json {
      print "[]"
    } else {
      print "No issues in scope. Use 'issue scope --add DIG-123' or 'issue start DIG-123'"
    }
    return
  }

  # Query each issue individually
  let issues = $all_ids | each { |id|
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

  # Collect all PR numbers for caching
  let all_pr_nums = $issues | each { |issue|
    let prs = $issue.attachments.nodes | where { |a| $a.sourceType? == "github" or ($a.url | str contains "github.com") }
    $prs | each { |p|
      let url = $p.url
      if ($url | str contains "/pull/") {
        $url | split row "/pull/" | last | split row "/" | first | into int
      } else { null }
    } | compact
  } | flatten | uniq

  # Cache PR numbers for prompt
  set-cached-prs $all_pr_nums

  # Show all scoped issues
  print $"(ansi cyan_bold)Scope:(ansi reset) ($all_ids | str join ', ')\n"

  for issue in $issues {
    let prs = $issue.attachments.nodes | where { |a| $a.sourceType? == "github" or ($a.url | str contains "github.com") }
    let pr_nums = $prs | each { |p|
      # Extract PR number from URL like https://github.com/org/repo/pull/42
      let url = $p.url
      if ($url | str contains "/pull/") {
        let num = $url | split row "/pull/" | last | split row "/" | first
        $"#($num)"
      } else { null }
    } | compact

    let pr_str = if ($pr_nums | length) > 0 { $" (ansi magenta)($pr_nums | str join ' ')(ansi reset)" } else { "" }

    print $"(ansi green_bold)($issue.identifier)(ansi reset) ($issue.state.name)($pr_str)"
    print $"  ($issue.title)"
  }
}

# Mark issue as done
export def "main done" [
  id?: string     # Issue ID (uses first in scope if not specified)
  --force (-f)    # Skip warnings and mark done anyway
] {
  let issue_id = if $id != null { $id } else { get-current }
  if $issue_id == null {
    exit-error "No issue specified and none in scope" --hint "Use 'issue done DIG-123' or add issues with 'issue scope --add'"
  }

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

# Show PRs linked to scoped issues
export def "main pr" [
  --json (-j)     # Output as JSON
] {
  let issue_ids = (get-current-issues)
  if ($issue_ids | length) == 0 {
    exit-error "No issues in scope" --hint "Use 'issue scope --add DIG-123' or 'issue start DIG-123'"
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

# State management for current issues
# Supports multiple current issues per repo via JSON format

# Get all current issues as list
export def get-current-issues [] {
  if (".issue" | path exists) {
    let content = (open ".issue" | str trim)
    # Detect format: JSON starts with {, old format is plain text
    if ($content | str starts-with "{") {
      try {
        let data = ($content | from json)
        $data.issues | default []
      } catch {
        []  # Corrupted JSON, return empty
      }
    } else if ($content | is-empty) {
      []
    } else {
      # Old format: single issue ID as plain text
      [$content]
    }
  } else {
    []
  }
}

# Get first/primary current issue (backward compatible)
export def get-current [] {
  let issues = (get-current-issues)
  if ($issues | length) > 0 { $issues.0 } else { null }
}

# Add an issue to the current list
export def add-current [id: string] {
  let issues = (get-current-issues)
  if not ($id in $issues) {
    let new_issues = ($issues | append $id)
    { issues: $new_issues, updated: (date now | format date "%Y-%m-%dT%H:%M:%SZ") }
      | to json | save -f ".issue"
  }
}

# Remove an issue from the current list
export def remove-current [id: string] {
  let issues = (get-current-issues)
  let new_issues = ($issues | where { |i| $i != $id })
  if ($new_issues | length) == 0 {
    rm -f ".issue"
  } else {
    { issues: $new_issues, updated: (date now | format date "%Y-%m-%dT%H:%M:%SZ") }
      | to json | save -f ".issue"
  }
}

# Set single issue (replaces list - for backward compat)
export def set-current [id: string] {
  { issues: [$id], updated: (date now | format date "%Y-%m-%dT%H:%M:%SZ") }
    | to json | save -f ".issue"
}

# Clear all current issues
export def clear-current [] {
  if (".issue" | path exists) {
    rm ".issue"
  }
}

# Slugify a string for git branch names
export def slugify [s: string] {
  $s
  | str downcase
  | str replace -ra '[^a-z0-9]+' '-'
  | str replace -r '^-|-$' ''
  | str substring 0..50
}

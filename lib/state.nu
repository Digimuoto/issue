# State management for current issue

# Get the current issue ID from .issue file
export def get-current [] {
  if (".issue" | path exists) {
    open ".issue" | str trim
  } else {
    null
  }
}

# Set the current issue ID
export def set-current [id: string] {
  $id | save -f ".issue"
}

# Clear the current issue
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

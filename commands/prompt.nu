# Prompt integration for Starship
# Fast output for shell prompt display - no API calls

use ../lib/state.nu [get-current-issues]

# Generate prompt output for Starship
export def "main prompt" [
  --no-links      # Disable OSC 8 hyperlinks
  --ids           # Show issue IDs instead of count
] {
  let issues = (get-current-issues)

  if ($issues | length) == 0 {
    # No output = starship hides the module
    return
  }

  let icon = ""  # Nerd Font ticket icon
  let count = ($issues | length)
  let first_id = $issues.0

  if $ids {
    # Show all issue IDs
    if $no_links {
      $"($icon) ($issues | str join ' ')"
    } else {
      # OSC 8 hyperlink for each issue
      let linked = $issues | each { |id|
        let url = $"https://linear.app/issue/($id)"
        $"\u{1b}]8;;($url)\u{1b}\\($id)\u{1b}]8;;\u{1b}\\"
      } | str join " "
      $"($icon) ($linked)"
    }
  } else {
    # Show icon with count
    if $no_links {
      $"($icon) ($count)"
    } else {
      # OSC 8 hyperlink to first issue
      let url = $"https://linear.app/issue/($first_id)"
      $"\u{1b}]8;;($url)\u{1b}\\($icon) ($count)\u{1b}]8;;\u{1b}\\"
    }
  }
}

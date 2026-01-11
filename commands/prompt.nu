# Prompt integration for Starship
# Fast output for shell prompt display - no API calls

use ../lib/state.nu [get-current-issues, get-cached-prs]

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

  let icon = "󰓹"  # Nerd Font ticket icon
  let prs = (get-cached-prs)

  # Build PR string (PRs are records: {num, issue} or legacy: just numbers)
  let pr_str = if ($prs | length) > 0 {
    # Check if new format (records) or legacy (numbers)
    let first = $prs.0
    let is_record = ($first | describe | str starts-with "record")

    if $no_links or not $is_record {
      # No links or legacy format
      let pr_parts = if $is_record {
        $prs | each { |p| $"#($p.num)" }
      } else {
        $prs | each { |n| $"#($n)" }
      }
      $" ($pr_parts | str join ' ')"
    } else {
      # OSC 8 hyperlink for each PR -> Linear issue page
      let pr_parts = $prs | each { |p|
        let url = $"https://linear.app/issue/($p.issue)"
        $"\u{1b}]8;;($url)\u{1b}\\#($p.num)\u{1b}]8;;\u{1b}\\"
      } | str join " "
      $" ($pr_parts)"
    }
  } else { "" }

  if $ids {
    # Show all issue IDs + PRs
    if $no_links {
      $"($icon) ($issues | str join ' ')($pr_str)"
    } else {
      # OSC 8 hyperlink for each issue
      let linked = $issues | each { |id|
        let url = $"https://linear.app/issue/($id)"
        $"\u{1b}]8;;($url)\u{1b}\\($id)\u{1b}]8;;\u{1b}\\"
      } | str join " "
      $"($icon) ($linked)($pr_str)"
    }
  } else {
    # Show icon with count + PRs
    let count = ($issues | length)
    if $no_links {
      $"($icon) ($count)($pr_str)"
    } else {
      # OSC 8 hyperlink to first issue
      let first_id = $issues.0
      let url = $"https://linear.app/issue/($first_id)"
      $"\u{1b}]8;;($url)\u{1b}\\($icon) ($count)\u{1b}]8;;\u{1b}\\($pr_str)"
    }
  }
}

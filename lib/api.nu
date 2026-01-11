# Linear API helpers

# Print error and exit
export def exit-error [msg: string, --hint: string] {
  print -e $"(ansi red_bold)error:(ansi reset) ($msg)"
  if $hint != null { print -e $"  (ansi cyan)hint:(ansi reset) ($hint)" }
  exit 1
}

export def get-api-key [] {
  let key = ($env | get -o LINEAR_API_KEY | default "")
  if $key == "" {
    exit-error "LINEAR_API_KEY not set" --hint "Get your API key from https://linear.app/settings/api"
  }
  $key
}

export def linear-query [query: string, variables: record = {}] {
  let api_key = (get-api-key)
  let resp = try {
    http post https://api.linear.app/graphql --content-type application/json --headers [Authorization $api_key] --allow-errors { query: $query, variables: $variables }
  } catch { |e|
    let msg = $e.msg? | default "unknown error"
    if ($msg | str contains "Network failure") {
      exit-error "HTTP request failed: Check LINEAR_API_KEY is valid and network is available"
    } else {
      exit-error $"HTTP request failed: ($msg)"
    }
  }
  if ($resp | get -o errors | default null) != null {
    let msg = $resp.errors.0.message? | default ($resp.errors | to json)
    # Improve common error messages
    let friendly_msg = if ($msg | str starts-with "Entity not found") {
      # "Entity not found: Issue" -> "Issue not found"
      $msg | str replace "Entity not found: " "" | $"($in) not found"
    } else if ($msg | str contains "not found") {
      $msg
    } else {
      $"Linear API: ($msg)"
    }
    exit-error $friendly_msg
  }
  $resp.data
}

export def truncate [n: int] {
  if ($in | str length) > $n { $"($in | str substring 0..$n)..." } else { $in }
}

export def map-status [s: string] {
  { backlog: "Backlog", todo: "Todo", inprogress: "In Progress", done: "Done", canceled: "Canceled" }
  | get -o $s
  | default $s
}

# Open content in $EDITOR and return edited content
# Returns null if user aborts (empty file or no changes)
export def edit-in-editor [content: string, suffix: string = ".md"] {
  let editor = ($env | get -o EDITOR | default "vi")
  let tmp = (mktemp --suffix $suffix)
  $content | save -f $tmp

  # Get original checksum
  let original = (open $tmp --raw | hash md5)

  # Open editor
  run-external $editor $tmp

  # Check if file was modified
  let edited = (open $tmp --raw)
  let new_hash = ($edited | hash md5)
  rm $tmp

  if $new_hash == $original {
    null  # No changes
  } else {
    $edited
  }
}

# Read content from file path or stdin (if path is "-")
export def read-content-file [path: string] {
  if $path == "-" {
    # Read from stdin
    $in | collect
  } else if ($path | path exists) {
    open $path --raw
  } else {
    exit-error $"File not found: ($path)"
  }
}

# Parse markdown content: first H1 is title, rest is body
# Returns {title, body} or error if no H1 found
export def parse-markdown-doc [content: string] {
  let lines = ($content | lines)

  # Find first H1
  let h1_idx = ($lines | enumerate | where { |l| $l.item | str starts-with "# " } | first)
  if $h1_idx == null {
    exit-error "Invalid format: missing title" --hint "First line must be a H1 heading: # Your Title"
  }

  let title = ($h1_idx.item | str replace -r "^# " "" | str trim)
  if ($title | is-empty) {
    exit-error "Invalid format: empty title" --hint "Title cannot be empty"
  }

  # Everything after H1 is the body
  let body_lines = ($lines | skip ($h1_idx.index + 1))
  let body = ($body_lines | str join "\n" | str trim)

  { title: $title, body: $body }
}

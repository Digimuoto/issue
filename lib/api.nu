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

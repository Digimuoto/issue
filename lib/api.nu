# Linear API helpers

export def exit-error [msg: string] {
  print $"(ansi red_bold)[ERROR](ansi reset): ($msg)"
  exit 1
}

export def get-api-key [] {
  let key = ($env | get -o LINEAR_API_KEY | default "")
  if $key == "" {
    exit-error "LINEAR_API_KEY not set. Get your key from https://linear.app/settings/api"
  }
  $key
}

export def linear-query [query: string, variables: record = {}] {
  let api_key = (get-api-key)
  let resp = try {
    http post https://api.linear.app/graphql --content-type application/json --headers [Authorization $api_key] { query: $query, variables: $variables }
  } catch { |e|
    exit-error $"HTTP request failed: ($e.msg? | default 'unknown error')"
  }
  if ($resp | get -o errors | default null) != null {
    exit-error $"Linear API: ($resp.errors.0.message? | default ($resp.errors | to json))"
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

# Epic commands

use ../lib/api.nu [linear-query]

# Epic management
export def "main epic" [] {
  print "Epic commands - use 'issue epic --help' for usage"
}

# List epics (issues with 'epic' label)
export def "main epic list" [
  --json (-j)  # Output as JSON
] {
  let data = (linear-query r#'
    query {
      issues(filter: { labels: { name: { eq: "epic" } } }, first: 50) {
        nodes { identifier title state { name } children { nodes { identifier } } }
      }
    }
  '#)

  let result = $data.issues.nodes | each { |e| {
    id: $e.identifier
    title: $e.title
    status: $e.state.name
    childCount: ($e.children.nodes | length)
  }}

  if $json { $result | to json } else {
    $result | each { |e| { ID: $e.id, Status: $e.status, Title: $e.title, Children: $e.childCount } }
  }
}

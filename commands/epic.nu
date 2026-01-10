# Epic commands

use ../lib/api.nu [linear-query]

# Epic management
export def "main epic" [] {
  print "Epic commands - use 'issue epic --help' for usage"
}

# List epics (issues with 'epic' label)
export def "main epic list" [] {
  let data = (linear-query r#'
    query {
      issues(filter: { labels: { name: { eq: "epic" } } }, first: 50) {
        nodes { identifier title state { name } children { nodes { identifier } } }
      }
    }
  '#)

  $data.issues.nodes | each { |e| {
    ID: $e.identifier
    Status: $e.state.name
    Title: $e.title
    Children: ($e.children.nodes | length)
  }}
}

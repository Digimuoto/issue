# Search commands

use ../lib/api.nu [linear-query]
use ../lib/ui.nu [truncate]

# Full-text search across issues
export def "main search" [
  query: string          # Search query
  --limit (-n): int = 25 # Max results
  --json (-j)            # Output as JSON
] {
  let data = (linear-query r#'
    query($term: String!, $limit: Int!) {
      searchIssues(term: $term, first: $limit) {
        nodes {
          identifier title
          state { name }
          priority
          labels { nodes { name } }
          assignee { name }
          parent { identifier }
        }
      }
    }
  '# { term: $query, limit: $limit })

  let issues = $data.searchIssues.nodes
  if ($issues | length) == 0 {
    if $json { print "[]" } else { print $"No results for '($query)'" }
    return
  }

  let result = $issues | each { |i| {
    id: $i.identifier
    title: $i.title
    status: $i.state.name
    priority: $i.priority
    labels: ($i.labels.nodes | get name)
    assignee: ($i.assignee?.name? | default null)
    epic: ($i.parent?.identifier? | default null)
  }}

  if $json { $result | to json } else {
    $result | each { |i| {
      ID: $i.id
      Status: $i.status
      Priority: $i.priority
      Title: ($i.title | truncate 45)
      Labels: ($i.labels | str join ", ")
      Assignee: ($i.assignee | default "-")
      Epic: ($i.epic | default "-")
    }}
  }
}

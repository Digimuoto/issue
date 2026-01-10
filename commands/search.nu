# Search commands

use ../lib/api.nu [linear-query, truncate]

# Full-text search across issues
export def "main search" [
  query: string          # Search query
  --limit (-n): int = 25 # Max results
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
    print $"No results for '($query)'"
    return
  }

  $issues | each { |i| {
    ID: $i.identifier
    Status: $i.state.name
    Priority: $i.priority
    Title: ($i.title | truncate 45)
    Labels: ($i.labels.nodes | get name | str join ", ")
    Assignee: ($i.assignee?.name? | default "-")
    Epic: ($i.parent?.identifier? | default "-")
  }}
}

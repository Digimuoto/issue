# Document commands

use ../lib/api.nu [exit-error, linear-query, truncate]
use ../lib/resolvers.nu [get-doc-uuid]

# Document management
export def "main doc" [] {
  print "Document commands - use 'issue doc --help' for usage"
}

# List documents
export def "main doc list" [
  --project (-p): string   # Filter by project
  --limit (-n): int = 20
  --json (-j)              # Output as JSON
] {
  let data = (linear-query r#'
    query($first: Int!) {
      documents(first: $first) {
        nodes { slugId title project { name } updatedAt }
      }
    }
  '# { first: $limit })

  let result = $data.documents.nodes
  | where { |d| $project == null or $d.project?.name? == $project }
  | each { |d| {
    id: $d.slugId
    title: $d.title
    project: ($d.project?.name? | default null)
    updatedAt: $d.updatedAt
  }}

  if $json { $result | to json } else {
    $result | each { |d| {
      ID: $d.id
      Title: ($d.title | truncate 40)
      Project: ($d.project | default "-")
      Updated: ($d.updatedAt | into datetime | format date "%Y-%m-%d")
    }}
  }
}

# Show document
export def "main doc show" [
  id: string
  --json (-j)  # Output as JSON
] {
  let data = (linear-query r#'
    query($id: String!) {
      document(id: $id) { title content url project { name } creator { name } updatedAt }
    }
  '# { id: $id })

  let d = $data.document
  if $d == null { exit-error $"Document '($id)' not found" }

  if $json {
    return ({
      id: $id
      title: $d.title
      content: $d.content
      url: $d.url
      project: ($d.project?.name? | default null)
      creator: ($d.creator?.name? | default null)
      updatedAt: $d.updatedAt
    } | to json)
  }

  print $"(ansi green_bold)($d.title)(ansi reset)"
  print $"(ansi cyan)URL:(ansi reset) ($d.url)"
  print $"(ansi cyan)Project:(ansi reset) ($d.project?.name? | default '-')"
  print $"(ansi cyan)Updated:(ansi reset) ($d.updatedAt | into datetime | format date '%Y-%m-%d %H:%M')\n"
  print $d.content
}

# Create document
export def "main doc create" [
  title: string
  --project (-p): string   # Project name (required)
  --content (-c): string
] {
  if $project == null { exit-error "Project required. Use --project <name>" }

  let input = ({ title: $title, project: $project }
    | merge (if $content != null { { content: $content } } else { {} })
  )

  let data = (linear-query r#'
    mutation($input: DocumentCreateInput!) {
      documentCreate(input: $input) { success document { slugId title url } }
    }
  '# { input: $input })

  if $data.documentCreate.success {
    let d = $data.documentCreate.document
    print $"Created: ($d.title)\nURL: ($d.url)\nID: ($d.slugId)"
  } else { exit-error "Failed to create document" }
}

# Edit document
export def "main doc edit" [
  id: string
  --title (-t): string
  --content (-c): string
] {
  if $title == null and $content == null { exit-error "Specify --title or --content" }

  let uuid = (get-doc-uuid $id)
  let input = ({}
    | merge (if $title != null { { title: $title } } else { {} })
    | merge (if $content != null { { content: $content } } else { {} })
  )

  let data = (linear-query r#'
    mutation($id: String!, $input: DocumentUpdateInput!) {
      documentUpdate(id: $id, input: $input) { success document { title } }
    }
  '# { id: $uuid, input: $input })

  if $data.documentUpdate.success { print $"Updated: ($data.documentUpdate.document.title)" } else { exit-error "Failed to update document" }
}

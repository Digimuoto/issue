# Label commands

use ../lib/api.nu [exit-error, linear-query]

# Label management
export def "main label" [] {
  print "Label commands - use 'issue label --help' for usage"
}

# List labels
export def "main label list" [
  --groups (-g)  # Show only label groups
] {
  let data = (linear-query r#'{ issueLabels(first: 250) { nodes { id name color description isGroup parent { name } } } }'#)
  let labels = $data.issueLabels.nodes

  if $groups {
    $labels | where isGroup == true | sort-by name
    | each { |l| { Name: $l.name, Color: $l.color, Description: ($l.description | default "-") } }
  } else {
    $labels | where isGroup != true | sort-by { |l| $l.parent?.name? | default "zzz" }
    | each { |l| { Name: $l.name, Group: ($l.parent?.name? | default "-"), Color: $l.color } }
  }
}

# Create label
export def "main label add" [
  name: string             # Label name
  --color (-c): string     # Hex color
  --group (-g): string     # Parent group name
  --description (-d): string
] {
  let parent_id = if $group != null {
    let data = (linear-query r#'query($name: String!) { issueLabels(filter: { name: { eq: $name } }) { nodes { id } } }'# { name: $group })
    if ($data.issueLabels.nodes | length) == 0 { exit-error $"Label group '($group)' not found" }
    $data.issueLabels.nodes.0.id
  } else { null }

  let input = ({ name: $name }
    | merge (if $color != null { { color: $color } } else { {} })
    | merge (if $description != null { { description: $description } } else { {} })
    | merge (if $parent_id != null { { parentId: $parent_id } } else { {} })
  )

  let data = (linear-query r#'
    mutation($input: IssueLabelCreateInput!) {
      issueLabelCreate(input: $input) { success issueLabel { name color } }
    }
  '# { input: $input })

  if $data.issueLabelCreate.success { print $"Created: ($data.issueLabelCreate.issueLabel.name) (($data.issueLabelCreate.issueLabel.color))" } else { exit-error "Failed to create label" }
}

# Delete label
export def "main label delete" [
  name: string  # Label name to delete
] {
  # Find the label by name
  let data = (linear-query r#'query($name: String!) { issueLabels(filter: { name: { eq: $name } }) { nodes { id name } } }'# { name: $name })
  if ($data.issueLabels.nodes | length) == 0 { exit-error $"Label '($name)' not found" }
  let label = $data.issueLabels.nodes.0

  let result = (linear-query r#'
    mutation($id: String!) {
      issueLabelDelete(id: $id) { success }
    }
  '# { id: $label.id })

  if $result.issueLabelDelete.success { print $"Deleted: ($label.name)" } else { exit-error "Failed to delete label" }
}

# Edit label
export def "main label edit" [
  name: string              # Label name to edit
  --new-name (-n): string   # New label name
  --color (-c): string      # New hex color
  --group (-g): string      # New parent group name
  --description (-d): string
] {
  # Find the label by name
  let data = (linear-query r#'query($name: String!) { issueLabels(filter: { name: { eq: $name } }) { nodes { id name } } }'# { name: $name })
  if ($data.issueLabels.nodes | length) == 0 { exit-error $"Label '($name)' not found" }
  let label = $data.issueLabels.nodes.0

  let parent_id = if $group != null {
    let pdata = (linear-query r#'query($name: String!) { issueLabels(filter: { name: { eq: $name } }) { nodes { id } } }'# { name: $group })
    if ($pdata.issueLabels.nodes | length) == 0 { exit-error $"Label group '($group)' not found" }
    $pdata.issueLabels.nodes.0.id
  } else { null }

  let input = ({}
    | merge (if $new_name != null { { name: $new_name } } else { {} })
    | merge (if $color != null { { color: $color } } else { {} })
    | merge (if $description != null { { description: $description } } else { {} })
    | merge (if $parent_id != null { { parentId: $parent_id } } else { {} })
  )

  if ($input | columns | length) == 0 {
    print "No changes specified. Use --new-name, --color, --group, or --description"
    return
  }

  let result = (linear-query r#'
    mutation($id: String!, $input: IssueLabelUpdateInput!) {
      issueLabelUpdate(id: $id, input: $input) {
        success
        issueLabel { name color }
      }
    }
  '# { id: $label.id, input: $input })

  if $result.issueLabelUpdate.success {
    print $"Updated: ($result.issueLabelUpdate.issueLabel.name) (($result.issueLabelUpdate.issueLabel.color))"
  } else { exit-error "Failed to update label" }
}

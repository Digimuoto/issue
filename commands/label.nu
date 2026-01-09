# Label commands

use ../lib/api.nu [exit-error, linear-query]

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

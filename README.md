# Linear Issue CLI

Command-line interface for Linear issue management.

## Installation

### Run directly from GitHub

```bash
nix run github:Digimuoto/issue -- list
nix run github:Digimuoto/issue -- show DIG-123
```

### Add to your flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    issue.url = "github:Digimuoto/issue";
  };

  outputs = { self, nixpkgs, issue, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          issue.packages.${system}.default
        ];
      };
    };
}
```

### Add to devShell packages

```nix
devShells.default = pkgs.mkShell {
  packages = [
    inputs.issue.packages.${system}.default
  ];
};
```

## Setup

Export your Linear API key:

```bash
export LINEAR_API_KEY="lin_api_..."
```

Get your key at: https://linear.app/settings/api

## Usage

```bash
# List issues
issue list
issue list --status todo
issue list --assignee me
issue list --cycle current
issue list --blocked        # Only blocked issues
issue list --blocking       # Only issues that block others

# Show issue details
issue show DIG-123
issue show DIG-123 --relations  # Include blocking/blocked-by

# Create issue
issue create "Fix bug" --type bug --label urgent

# Update status
issue status DIG-123 inprogress

# Add comment
issue comment DIG-123 "Working on this"

# Edit issue
issue edit DIG-123 --assignee me --priority 2

# Epics
issue epic list

# Labels
issue label list
issue label add "new-label" --group "Type"

# Documents
issue doc list
issue doc show doc-slug
issue doc create "New Doc" --project "Project Name"

# Sprint/Cycle
issue cycle
issue cycle --all
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `LINEAR_API_KEY` | Required. Your Linear API key |
| `LINEAR_TEAM` | Optional. Team name for multi-team workspaces |
| `LINEAR_PROJECT` | Optional. Default project name |

## Commands

| Command | Description |
|---------|-------------|
| `list` | List issues with filters |
| `show <id>` | Show issue details |
| `create <title>` | Create new issue |
| `status <id> <status>` | Update issue status |
| `edit <id>` | Edit issue fields |
| `comment <id> <body>` | Add comment |
| `comments <id>` | Show comments |
| `epic list` | List epics |
| `label list` | List labels |
| `label add <name>` | Create label |
| `doc list` | List documents |
| `doc show <id>` | Show document |
| `doc create <title>` | Create document |
| `doc edit <id>` | Edit document |
| `cycle` | Show current sprint |

## Status Values

- `backlog` - Backlog
- `todo` - Todo
- `inprogress` - In Progress
- `done` - Done
- `canceled` - Canceled

## Issue Types

- `feature` - Feature
- `bug` - Bug
- `refactor` - Refactor
- `docs` - Documentation
- `chore` - Chore

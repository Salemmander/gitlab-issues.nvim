# gitlab-issues.nvim

An unofficial GitLab issues picker for Neovim, powered by [`glab`](https://gitlab.com/gitlab-org/cli) and [`snacks.nvim`](https://github.com/folke/snacks.nvim).

Browse, filter, create, comment on, assign, close, and reopen GitLab issues from a fast Snacks picker.

## Features

- Browse GitLab issues visible to your authenticated `glab` account
- Optionally scope issues to a default GitLab group
- Filter by repo, assignee, state, current group, or current repo
- Preview issue metadata and Markdown descriptions
- Create issues from Neovim
- Assign or unassign yourself
- Add comments
- Close and reopen issues

## Requirements

| Dependency | Notes |
| --- | --- |
| Neovim | Requires `vim.system` |
| [`glab`](https://gitlab.com/gitlab-org/cli) | Used for GitLab authentication and API calls |
| [`snacks.nvim`](https://github.com/folke/snacks.nvim) | Provides the picker UI |

Authenticate `glab` before using the plugin:

```sh
glab auth login
glab auth status
```

## Installation

With [`lazy.nvim`](https://github.com/folke/lazy.nvim):

```lua
{
  "Salemmander/gitlab-issues.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    -- Optional. Without a group, the picker starts with all visible issues.
    group = "my-gitlab-group",
  },
}
```

For self-hosted GitLab:

```lua
{
  "Salemmander/gitlab-issues.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    group = "my-group",
    gitlab_url = "https://gitlab.example.com",
  },
}
```

## Usage

Default global keymaps are enabled automatically.

| Key | Action |
| --- | --- |
| `<leader>GI` | Show all issues |
| `<leader>Go` | Show open issues only |
| `<leader>GO` | Show current repo issues |
| `<leader>GC` | Create an issue |

Inside the picker:

| Key | Action |
| --- | --- |
| `<C-o>` | Open issue in browser |
| `<C-e>` | Assign or unassign yourself |
| `<C-f>` | Toggle assigned-to-me filter |
| `<C-g>` | Toggle current repo scope |
| `<C-s>` | Cycle issue state filter |
| `<C-r>` | Filter by repo |
| `<C-y>` | Pick active group |
| `<C-t>` | Create issue |
| `<C-x>` | Close or reopen issue |
| `<C-b>` | Add comment |

## Configuration

Defaults:

```lua
{
  group = nil,
  gitlab_url = "https://gitlab.com",
  glab_cmd = "glab",
  keymaps = {
    issues = "<leader>GI",
    open_issues = "<leader>Go",
    current_repo_open_issues = "<leader>GO",
    create_issue = "<leader>GC",
  },
}
```

`group` is optional.

When `group` is unset, the picker starts from issues visible to the authenticated account:

```sh
glab api issues --paginate
```

When `group` is set, the picker uses group-scoped issue listing.

### Keymaps

Disable all default global keymaps:

```lua
{
  "Salemmander/gitlab-issues.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    keymaps = false,
  },
}
```

Override keymaps:

```lua
{
  "Salemmander/gitlab-issues.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    keymaps = {
      issues = "<leader>gi",
      open_issues = "<leader>go",
      current_repo_open_issues = "<leader>gO",
      create_issue = "<leader>gc",
    },
  },
}
```

Set an individual keymap to `false` or `nil` to skip it.

## API

Show the issue picker:

```lua
require("gitlab-issues").issues()
```

Show open issues only:

```lua
require("gitlab-issues").issues({ state = "opened" })
```

Show open issues for the current GitLab repo:

```lua
require("gitlab-issues").issues({
  current_repo = true,
  state = "opened",
})
```

Create an issue:

```lua
require("gitlab-issues").create_issue()
```

## Notes

- This plugin shells out to `glab`; it does not manage GitLab tokens directly.
- Current repo detection uses the local `origin` remote and `gitlab_url`.
- This project is not affiliated with GitLab.

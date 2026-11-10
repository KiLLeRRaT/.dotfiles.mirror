# Neovim

## Config Location
`/nvim-lua`

## Per-host plugin toggles

`lua/killerrat/plugins/hosts.lua` maps hostname → `{ ["plugin"] = false }` (absent = enabled). Every
lazy spec honours it via `defaults.cond`; each `_*.lua` module loads via `pcall`, so one broken module
no longer takes the rest down.

| Command / setting                        | Action                                                        |
|------------------------------------------|---------------------------------------------------------------|
| `:KillerratPlugins`                      | Table of every module: ok / skipped / failed                  |
| `:KillerratPlugins!`                     | Same, in a split with the full error text                     |
| startup prompt                           | On failure: Disable (writes hosts.lua) / Skip / Show error / Skip all |
| `vim.g.killerrat_plugin_prompt = false`  | Silence the prompt (set it in `init.lua` or via `--cmd`)      |
| `~/.config/nvim/nvim-plugins check --host H`   | Headless load as host H, exit 1 on any failure          |
| `~/.config/nvim/nvim-plugins list --host H`    | Show H's overrides from hosts.lua                       |
| `~/.config/nvim/nvim-plugins disable nvim-dap` | Set `plugins[$HOST]["nvim-dap"] = false` (surgical edit)|
| `~/.config/nvim/nvim-plugins enable nvim-dap`  | Flip it back to `true`                                  |

## Key Bindings

`<leader>` is set to `<space>`


### Window Management

| Key      | Action                                                     | Plugin            |
|----------|------------------------------------------------------------|-------------------|
| `<c-w>h` | Focus window to the left                                   |                   |
| `<c-w>j` | Focus window to the below                                  |                   |
| `<c-w>k` | Focus window to the above                                  |                   |
| `<c-w>l` | Focus window to the right                                  |                   |
| `<c-e>`  | Enter resize mode, then use hjkl to resize, enter for done | simeji/winresizer |
| `:clo`   | Closes the current window                                  |                   |


### Git

| Key          | Action     | Plugin       |
|--------------|------------|--------------|
| `<leader>gs` | Git Status | vim-fugitive |
| ``           |            |              |
| ``           |            |              |
| ``           |            |              |
| ``           |            |              |
| ``           |            |              |
| ``           |            |              |
| ``           |            |              |
| ``           |            |              |
| ``           |            |              |
| ``           |            |              |

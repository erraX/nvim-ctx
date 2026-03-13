# nvim-ctx

`nvim-ctx` sends a visual selection as a compact file reference into a running AI CLI agent in `kitty`.

Default output:

```text
@path/to/file#12-18
```

## Requirements

- Neovim `0.10+`
- `kitty` with remote control enabled

`kitty.conf` needs:

```conf
allow_remote_control yes
```

If Neovim is not running inside the same kitty instance as the agent, also expose a control socket with `listen_on` or `KITTY_LISTEN_ON`.

## Installation

Use your normal plugin manager. Example with `lazy.nvim`:

```lua
{
  'niminjie/nvim-ctx',
  opts = {
    agent = 'codex',
  },
}
```

## Usage

Pick the destination kitty window once:

```vim
:NvimCtxPickTarget
```

Visual select lines and send them:

```vim
:'<,'>NvimCtxSend
```

Sample visual-mode mapping:

```lua
vim.keymap.set('v', '<leader>ac', function()
  vim.cmd("'<,'>NvimCtxSend")
end, { desc = 'Send selection to AI CLI' })
```

Clear the cached target:

```vim
:NvimCtxClearTarget
```

## Configuration

```lua
require('nvim-ctx').setup({
  agent = 'codex',
  path_mode = 'git',
  formatters = {
    codex = '@{{path}}#{{range}}',
    claude = '@{{path}}#{{range}}',
    custom = 'file={{path}} lines={{start_line}}-{{end_line}}',
  },
  kitty = {
    listen_on = nil,
  },
})
```

Template variables:

- `path`
- `start_line`
- `end_line`
- `range`

## Commands

- `:NvimCtxSend`
- `:NvimCtxPickTarget`
- `:NvimCtxClearTarget`

## Tests

```sh
nvim --clean --headless -u tests/minimal_init.lua -c "lua dofile('tests/run.lua')" -c "qa!"
```

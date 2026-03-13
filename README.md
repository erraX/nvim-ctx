# nvim-ctx

`nvim-ctx` sends a visual selection as a compact file reference into a running AI CLI agent in `kitty`.

Default output:

```text
@path/to/file#12-18
```

The generated reference is also copied to the system clipboard by default, so you can paste it manually if `kitty` delivery fails.

When there is no visual selection, `nvim-ctx` sends file-only context:

```text
@path/to/file
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
  clipboard = {
    enabled = true,
    register = '+',
  },
  formatters = {
    codex = '@{{path}}{{line_suffix}}',
    claude = '@{{path}}{{line_suffix}}',
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
- `line_suffix`

## Commands

- `:NvimCtxSend`
- `:NvimCtxPickTarget`
- `:NvimCtxClearTarget`

## Tests

```sh
nvim --clean --headless -u tests/minimal_init.lua -c "lua dofile('tests/run.lua')" -c "qa!"
```

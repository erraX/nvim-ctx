local M = {}

local default_formatters = {
  codex = '@{{path}}{{line_suffix}}',
  claude = '@{{path}}{{line_suffix}}',
}

M.defaults = {
  agent = 'codex',
  formatters = default_formatters,
  path_mode = 'git',
  clipboard = {
    enabled = true,
    register = '+',
  },
  kitty = {
    listen_on = nil,
  },
}

local function deepcopy(value)
  return vim.deepcopy(value)
end

function M.merge(user_opts)
  local merged = deepcopy(M.defaults)
  user_opts = user_opts or {}

  if user_opts.formatters then
    merged.formatters = vim.tbl_extend('force', deepcopy(default_formatters), user_opts.formatters)
    user_opts = vim.tbl_extend('force', {}, user_opts)
    user_opts.formatters = nil
  else
    merged.formatters = deepcopy(default_formatters)
  end

  return vim.tbl_deep_extend('force', merged, user_opts)
end

return M

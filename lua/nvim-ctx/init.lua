local config = require('nvim-ctx.config')
local kitty = require('nvim-ctx.kitty')

local M = {}

M._state = {
  config = config.merge(),
  target = nil,
}

local function notify(message, level)
  local function emit()
    vim.notify(message, level or vim.log.levels.INFO, { title = 'nvim-ctx' })
  end

  if vim.in_fast_event() then
    vim.schedule(emit)
    return
  end

  emit()
end

local function normalize_path(path)
  return path:gsub('\\', '/')
end

local function canonicalize_path(path)
  local real = vim.uv.fs_realpath(path)
  return normalize_path(vim.fs.normalize(real or path))
end

local function dirname(path)
  return vim.fn.fnamemodify(path, ':h')
end

local function path_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

local function find_git_root(path)
  local search = dirname(path)
  local git_dir = vim.fs.find('.git', {
    path = search,
    upward = true,
    stop = vim.loop.os_homedir(),
  })[1]

  if not git_dir then
    return nil
  end

  return dirname(git_dir)
end

local function relative_to(base, path)
  local normalized_base = canonicalize_path(base)
  local normalized_path = canonicalize_path(path)
  local prefix = normalized_base .. '/'

  if normalized_path == normalized_base then
    return '.'
  end

  if normalized_path:sub(1, #prefix) == prefix then
    return normalized_path:sub(#prefix + 1)
  end

  return normalized_path
end

local function resolve_path(path_mode, bufname)
  local absolute = canonicalize_path(bufname)
  local base = canonicalize_path(vim.uv.cwd())

  if path_mode == 'git' then
    local git_root = find_git_root(absolute)
    if git_root then
      base = git_root
    end
  end

  return normalize_path(relative_to(base, absolute))
end

local function render_template(template, data)
  return (template:gsub('{{([%w_]+)}}', function(key)
    return tostring(data[key] or '')
  end))
end

local function line_range(start_line, end_line)
  if start_line == end_line then
    return tostring(start_line)
  end

  return string.format('%d-%d', start_line, end_line)
end

local function selection_from_marks()
  local start_pos = vim.api.nvim_buf_get_mark(0, '<')
  local end_pos = vim.api.nvim_buf_get_mark(0, '>')

  local start_line = start_pos[1]
  local end_line = end_pos[1]

  if start_line == 0 or end_line == 0 then
    return nil, 'no visual selection found'
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  return start_line, end_line
end

local function resolve_selection(opts)
  if opts and opts.line1 and opts.line2 and opts.line1 > 0 and opts.line2 > 0 then
    local start_line = math.min(opts.line1, opts.line2)
    local end_line = math.max(opts.line1, opts.line2)
    return start_line, end_line
  end

  local start_line, end_line = selection_from_marks()
  if start_line and end_line then
    return start_line, end_line
  end

  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  return current_line, current_line
end

local function build_reference(bufname, start_line, end_line, opts)
  local cfg = M._state.config
  local agent = (opts and opts.agent) or cfg.agent
  local template = cfg.formatters[agent]

  if not template then
    return nil, string.format('unknown formatter preset: %s', agent)
  end

  local path = resolve_path((opts and opts.path_mode) or cfg.path_mode, bufname)
  local range = line_range(start_line, end_line)

  return render_template(template, {
    path = path,
    start_line = start_line,
    end_line = end_line,
    range = range,
  })
end

local function ensure_named_file(bufname)
  if bufname == '' then
    return nil, 'current buffer has no file name'
  end

  if not path_exists(bufname) then
    return nil, string.format('file does not exist on disk: %s', bufname)
  end

  return bufname
end

local function copy_to_clipboard(text)
  local clipboard = M._state.config.clipboard or {}
  if clipboard.enabled == false then
    return false, nil
  end

  local register = clipboard.register or '+'
  local ok, err = pcall(vim.fn.setreg, register, text)
  if not ok then
    return false, err
  end

  return true, nil
end

local function transport_error_message(message, copied_to_clipboard)
  if copied_to_clipboard then
    return string.format('%s; reference copied to clipboard', message)
  end

  return message
end

local function ensure_target(callback)
  if M._state.target then
    kitty.window_exists(M._state.target.id, M._state.config.kitty, function(exists, err)
      if err then
        callback(nil, err)
        return
      end

      if exists then
        callback(M._state.target, nil)
        return
      end

      M._state.target = nil
      notify('cached kitty target no longer exists; pick a new one', vim.log.levels.WARN)
      kitty.select_target(M._state.config.kitty, function(choice, select_err)
        if select_err then
          callback(nil, select_err)
          return
        end

        M._state.target = choice
        callback(choice, nil)
      end)
    end)
    return
  end

  kitty.select_target(M._state.config.kitty, function(choice, err)
    if err then
      callback(nil, err)
      return
    end

    M._state.target = choice
    callback(choice, nil)
  end)
end

function M.setup(opts)
  M._state.config = config.merge(opts)
end

function M.pick_target()
  kitty.select_target(M._state.config.kitty, function(choice, err)
    if err then
      if err ~= 'selection cancelled' then
        notify(err, vim.log.levels.ERROR)
      end
      return
    end

    M._state.target = choice
    notify(string.format('kitty target set to %s', choice.label))
  end)
end

function M.clear_target()
  M._state.target = nil
  notify('cleared cached kitty target')
end

function M.send_selection(opts)
  opts = opts or {}

  local bufname, buf_err = ensure_named_file(vim.api.nvim_buf_get_name(0))
  if not bufname then
    notify(buf_err, vim.log.levels.ERROR)
    return
  end

  local start_line, end_line_or_err, maybe_err = resolve_selection(opts)
  local end_line = end_line_or_err
  local selection_err = maybe_err

  if not start_line then
    notify(end_line_or_err, vim.log.levels.ERROR)
    return
  end

  if selection_err then
    notify(selection_err, vim.log.levels.ERROR)
    return
  end

  local reference, ref_err = build_reference(bufname, start_line, end_line, opts)
  if not reference then
    notify(ref_err, vim.log.levels.ERROR)
    return
  end

  local copied_to_clipboard, clipboard_err = copy_to_clipboard(reference)
  if clipboard_err then
    notify('failed to copy reference to clipboard: ' .. clipboard_err, vim.log.levels.WARN)
  end

  ensure_target(function(target, target_err)
    if not target then
      if target_err ~= 'selection cancelled' then
        local guidance = 'kitty remote control unavailable; enable allow_remote_control yes and configure listen_on or KITTY_LISTEN_ON if needed'
        if target_err:find('kitty', 1, true) then
          notify(transport_error_message(guidance, copied_to_clipboard), vim.log.levels.ERROR)
        else
          notify(transport_error_message(target_err, copied_to_clipboard), vim.log.levels.ERROR)
        end
      end
      return
    end

    kitty.send_text(target.id, reference, M._state.config.kitty, function(ok, send_err)
      if not ok then
        M._state.target = nil
        notify(transport_error_message(send_err, copied_to_clipboard), vim.log.levels.ERROR)
        return
      end

      notify(string.format('sent %s to kitty window %s', reference, target.id))
    end)
  end)
end

M._test = {
  build_reference = build_reference,
  line_range = line_range,
  normalize_path = normalize_path,
  render_template = render_template,
  resolve_path = resolve_path,
  resolve_selection = resolve_selection,
  find_git_root = find_git_root,
  transport_error_message = transport_error_message,
  reset_state = function()
    M._state.target = nil
    M._state.config = config.merge()
  end,
}

return M

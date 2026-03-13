local M = {}

local function build_command(subcommand, args, opts)
  local cmd = { 'kitty' }

  if opts and opts.listen_on then
    vim.list_extend(cmd, { '@', '--to', opts.listen_on, subcommand })
  else
    vim.list_extend(cmd, { '@', subcommand })
  end

  if args then
    vim.list_extend(cmd, args)
  end

  return cmd
end

local function system(cmd, opts, on_exit)
  return vim.system(cmd, opts or {}, on_exit)
end

function M.list_windows(opts, callback)
  local cmd = build_command('ls', nil, opts)

  system(cmd, { text = true }, function(result)
    if result.code ~= 0 then
      callback(nil, result.stderr ~= '' and result.stderr or 'failed to run kitty @ ls')
      return
    end

    local ok, decoded = pcall(vim.json.decode, result.stdout)
    if not ok then
      callback(nil, 'failed to parse kitty window list')
      return
    end

    callback(decoded, nil)
  end)
end

local function process_label(process)
  if not process then
    return 'unknown'
  end

  if type(process.cmdline) == 'table' and #process.cmdline > 0 then
    return table.concat(process.cmdline, ' ')
  end

  return process.cwd or 'unknown'
end

local function candidate_priority(candidate)
  local lower = string.lower(candidate.process or '')
  if lower:find('codex', 1, true) or lower:find('claude', 1, true) then
    return 0
  end

  return 1
end

function M.flatten_windows(tree)
  local candidates = {}

  for _, os_window in ipairs(tree or {}) do
    for _, tab in ipairs(os_window.tabs or {}) do
      for _, window in ipairs(tab.windows or {}) do
        local process = window.foreground_processes and window.foreground_processes[1] or nil
        local entry = {
          id = window.id,
          os_window_id = os_window.id,
          tab_id = tab.id,
          tab_title = tab.title or '',
          window_title = window.title or '',
          cwd = window.cwd or (process and process.cwd) or '',
          process = process_label(process),
          is_self = window.is_self or false,
        }

        entry.label = string.format(
          '[%s] %s | %s | %s',
          entry.id,
          entry.tab_title ~= '' and entry.tab_title or 'untitled-tab',
          entry.window_title ~= '' and entry.window_title or 'untitled-window',
          entry.process
        )

        table.insert(candidates, entry)
      end
    end
  end

  table.sort(candidates, function(a, b)
    local pa = candidate_priority(a)
    local pb = candidate_priority(b)
    if pa ~= pb then
      return pa < pb
    end

    return a.id < b.id
  end)

  return candidates
end

function M.select_target(opts, callback)
  M.list_windows(opts, function(tree, err)
    if err then
      callback(nil, err)
      return
    end

    local candidates = M.flatten_windows(tree)
    if #candidates == 0 then
      callback(nil, 'no kitty windows found')
      return
    end

    vim.schedule(function()
      vim.ui.select(candidates, {
        prompt = 'Select kitty target',
        format_item = function(item)
          return item.label
        end,
      }, function(choice)
        if not choice then
          callback(nil, 'selection cancelled')
          return
        end

        callback(choice, nil)
      end)
    end)
  end)
end

function M.window_exists(target_id, opts, callback)
  local cmd = build_command('ls', { '--match', ('id:%s'):format(target_id) }, opts)

  system(cmd, { text = true }, function(result)
    if result.code ~= 0 then
      callback(false, result.stderr ~= '' and result.stderr or 'failed to validate kitty target')
      return
    end

    local ok, decoded = pcall(vim.json.decode, result.stdout)
    if not ok then
      callback(false, 'failed to parse kitty window list')
      return
    end

    local candidates = M.flatten_windows(decoded)
    callback(#candidates > 0, nil)
  end)
end

function M.send_text(target_id, text, opts, callback)
  local cmd = build_command('send-text', {
    '--match',
    ('id:%s'):format(target_id),
    '--stdin',
    '--bracketed-paste',
    'enable',
  }, opts)

  system(cmd, { text = true, stdin = text }, function(result)
    if result.code ~= 0 then
      callback(false, result.stderr ~= '' and result.stderr or 'failed to send text with kitty')
      return
    end

    callback(true, nil)
  end)
end

return M

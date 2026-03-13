local results = {
  passed = 0,
  failed = 0,
}

local function ok(condition, message)
  if not condition then
    error(message or 'assertion failed')
  end
end

local function eq(actual, expected, message)
  if actual ~= expected then
    error(message or string.format('expected %s, got %s', vim.inspect(expected), vim.inspect(actual)))
  end
end

local function test(name, fn)
  local status, err = pcall(fn)
  if status then
    results.passed = results.passed + 1
    return
  end

  results.failed = results.failed + 1
  io.stderr:write(string.format('FAIL %s\n%s\n', name, err))
end

local nvim_ctx = require('nvim-ctx')
local kitty = require('nvim-ctx.kitty')

local function with_temp_dir(fn)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local ok_status, err = pcall(fn, dir)
  vim.fn.delete(dir, 'rf')
  if not ok_status then
    error(err)
  end
end

test('line_range formats single and multi line selections', function()
  eq(nvim_ctx._test.line_range(12, 12), '12')
  eq(nvim_ctx._test.line_range(12, 18), '12-18')
end)

test('render_template replaces placeholders', function()
  eq(
    nvim_ctx._test.render_template('@{{path}}#{{range}}', {
      path = 'lua/mod.lua',
      range = '5-9',
    }),
    '@lua/mod.lua#5-9'
  )
end)

test('resolve_path prefers git relative paths', function()
  with_temp_dir(function(dir)
    vim.fn.mkdir(dir .. '/.git', 'p')
    vim.fn.mkdir(dir .. '/lua', 'p')
    local file = dir .. '/lua/mod.lua'
    vim.fn.writefile({ 'return true' }, file)

    eq(nvim_ctx._test.resolve_path('git', file), 'lua/mod.lua')
  end)
end)

test('resolve_path falls back to cwd relative paths', function()
  with_temp_dir(function(dir)
    local previous = vim.uv.cwd()
    local status, err = pcall(function()
      vim.cmd.cd(dir)
      vim.fn.mkdir(dir .. '/lua', 'p')
      local file = dir .. '/lua/mod.lua'
      vim.fn.writefile({ 'return true' }, file)

      eq(nvim_ctx._test.resolve_path('cwd', file), 'lua/mod.lua')
    end)
    vim.cmd.cd(previous)
    if not status then
      error(err)
    end
  end)
end)

test('build_reference uses configured formatter preset', function()
  nvim_ctx.setup({
    formatters = {
      custom = 'file={{path}} lines={{start_line}}:{{end_line}}',
    },
    agent = 'custom',
  })

  with_temp_dir(function(dir)
    vim.fn.mkdir(dir .. '/.git', 'p')
    local file = dir .. '/plugin.lua'
    vim.fn.writefile({ 'print("x")' }, file)

    eq(nvim_ctx._test.build_reference(file, 3, 7, {}), 'file=plugin.lua lines=3:7')
  end)

  nvim_ctx._test.reset_state()
end)

test('resolve_selection uses explicit command range', function()
  local start_line, end_line = nvim_ctx._test.resolve_selection({
    line1 = 8,
    line2 = 3,
  })

  eq(start_line, 3)
  eq(end_line, 8)
end)

test('resolve_selection falls back to current line in normal mode', function()
  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local start_line, end_line = nvim_ctx._test.resolve_selection({})

  eq(start_line, 2)
  eq(end_line, 2)

  vim.cmd.bdelete({ bang = true })
end)

test('flatten_windows prioritizes codex and claude processes', function()
  local tree = {
    {
      id = 1,
      tabs = {
        {
          id = 3,
          title = 'misc',
          windows = {
            {
              id = 22,
              title = 'shell',
              cwd = '/tmp',
              foreground_processes = {
                { cmdline = { 'zsh' } },
              },
            },
            {
              id = 10,
              title = 'codex',
              cwd = '/tmp',
              foreground_processes = {
                { cmdline = { 'codex' } },
              },
            },
          },
        },
      },
    },
  }

  local candidates = kitty.flatten_windows(tree)
  eq(candidates[1].id, 10)
  eq(candidates[2].id, 22)
end)

test('send_selection reuses cached kitty target and sends reference text', function()
  nvim_ctx._test.reset_state()

  local temp = vim.fs.joinpath(vim.uv.cwd(), 'tests', 'tmp-send.lua')
  vim.fn.writefile({ 'one', 'two', 'three' }, temp)
  vim.cmd.edit(temp)

  local sent = {}
  local system_calls = {}
  local original_system = vim.system
  local original_notify = vim.notify
  local original_select = vim.ui.select

  vim.notify = function() end
  vim.ui.select = function(items, _, on_choice)
    on_choice(items[1])
  end

  vim.system = function(cmd, opts, on_exit)
    table.insert(system_calls, { cmd = vim.deepcopy(cmd), opts = vim.deepcopy(opts) })

    if cmd[3] == 'ls' and cmd[4] == '--match' then
      on_exit({
        code = 0,
        stdout = vim.json.encode({
          {
            id = 1,
            tabs = {
              {
                id = 2,
                title = 'codex',
                windows = {
                  {
                    id = 10,
                    title = 'codex',
                    cwd = vim.uv.cwd(),
                    foreground_processes = {
                      {
                        cmdline = { 'codex' },
                        cwd = vim.uv.cwd(),
                      },
                    },
                  },
                },
              },
            },
          },
        }),
        stderr = '',
      })
    elseif cmd[3] == 'ls' then
      on_exit({
        code = 0,
        stdout = vim.json.encode({
          {
            id = 1,
            tabs = {
              {
                id = 2,
                title = 'codex',
                windows = {
                  {
                    id = 10,
                    title = 'codex',
                    cwd = vim.uv.cwd(),
                    foreground_processes = {
                      {
                        cmdline = { 'codex' },
                        cwd = vim.uv.cwd(),
                      },
                    },
                  },
                },
              },
            },
          },
        }),
        stderr = '',
      })
    elseif cmd[3] == 'send-text' then
      sent[#sent + 1] = opts.stdin
      on_exit({ code = 0, stdout = '', stderr = '' })
    else
      error('unexpected command: ' .. table.concat(cmd, ' '))
    end

    return {
      wait = function()
        return { code = 0, stdout = '', stderr = '' }
      end,
    }
  end

  nvim_ctx.send_selection({
    line1 = 2,
    line2 = 3,
  })

  vim.wait(100, function()
    return #sent == 1
  end)

  eq(sent[1], '@tests/tmp-send.lua#2-3')
  ok(nvim_ctx._state.target ~= nil, 'target should be cached after selection')

  vim.system = original_system
  vim.notify = original_notify
  vim.ui.select = original_select
  vim.cmd.bdelete({ bang = true })
  vim.fn.delete(temp)
end)

if results.failed > 0 then
  error(string.format('%d tests failed, %d passed', results.failed, results.passed))
end

print(string.format('%d tests passed', results.passed))

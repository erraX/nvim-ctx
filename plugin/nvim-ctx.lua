if vim.g.loaded_nvim_ctx then
  return
end

vim.g.loaded_nvim_ctx = 1

local nvim_ctx = require('nvim-ctx')

vim.api.nvim_create_user_command('NvimCtxSend', function(args)
  nvim_ctx.send_selection({
    line1 = args.line1,
    line2 = args.line2,
  })
end, {
  desc = 'Send the current visual selection as agent context',
  range = true,
})

vim.api.nvim_create_user_command('NvimCtxPickTarget', function()
  nvim_ctx.pick_target()
end, {
  desc = 'Pick the kitty window that receives agent context',
})

vim.api.nvim_create_user_command('NvimCtxClearTarget', function()
  nvim_ctx.clear_target()
end, {
  desc = 'Clear the cached kitty target',
})

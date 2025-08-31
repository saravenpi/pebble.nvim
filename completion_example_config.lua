-- Example configuration for pebble.nvim with completion
-- Add this to your Neovim configuration (init.lua or pebble.lua)

-- Basic setup with completion enabled (default)
require('pebble').setup({
  enable_completion = true,  -- Enable completion (default: true)
  auto_setup_keymaps = true, -- Enable default keymaps (default: true)
  global_keymaps = false,    -- Don't set global keymaps (default: false)
  
  completion = {
    -- Future completion options can be added here
  }
})

-- Alternative: Disable completion if you don't want it
-- require('pebble').setup({
--   enable_completion = false,
-- })

-- Manual completion setup (advanced users)
-- If you want more control over completion configuration:
-- require('pebble').setup({
--   enable_completion = false, -- Disable auto setup
-- })
-- 
-- -- Then manually setup completion
-- local pebble_completion = require('pebble.completion')
-- pebble_completion.setup({
--   -- Custom completion options here
-- })

-- Example nvim-cmp integration (if you're using nvim-cmp)
-- This is handled automatically, but you can customize:
local cmp = require('cmp')
cmp.setup.filetype('markdown', {
  sources = cmp.config.sources({
    { name = 'pebble_markdown_links', priority = 1000 },
    { name = 'nvim_lsp' },
  }, {
    { name = 'buffer' },
    { name = 'path' }
  })
})

-- Example keymaps for completion commands
vim.keymap.set('n', '<leader>mcs', '<cmd>PebbleCompletionStats<cr>', { desc = 'Show completion stats' })
vim.keymap.set('n', '<leader>mcr', '<cmd>PebbleCompletionRefresh<cr>', { desc = 'Refresh completion cache' })

-- You can also access completion programmatically
local function show_completion_info()
  local completion = require('pebble').get_completion()
  local stats = completion.get_stats()
  print('Completion cache has ' .. stats.cache_size .. ' files')
end

-- Create a command to show completion info
vim.api.nvim_create_user_command('ShowCompletionInfo', show_completion_info, { desc = 'Show completion info' })
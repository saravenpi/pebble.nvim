-- Pebble: Obsidian-style markdown link navigation for Neovim
-- Entry point for the plugin

if vim.g.loaded_pebble then
  return
end
vim.g.loaded_pebble = 1

-- Check if Neovim version is supported
if vim.fn.has('nvim-0.8') == 0 then
  vim.api.nvim_err_writeln('Pebble requires Neovim 0.8 or later')
  return
end

-- Set up default configuration and initialize the plugin
local pebble = require('pebble')

-- Initialize with default settings
pebble.setup({
  auto_setup_keymaps = true,  -- Automatically set up keymaps for markdown files
  global_keymaps = false      -- Don't set up global keymaps by default
})
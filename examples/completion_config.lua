-- Enhanced pebble.nvim completion configuration examples
-- Choose one of the configurations below based on your needs

-- 1. MINIMAL SETUP (just enable completion with defaults)
require('pebble').setup({
    completion = { enabled = true },
})

-- 2. SAFE SETUP (recommended for most users)
require('pebble').setup({
    completion = {
        enabled = true,
        debug = false,
        prevent_conflicts = true, -- Prevent conflicts with existing sources
        nvim_cmp = {
            enabled = true,
            priority = 100,
            max_item_count = 25,
            filetype_setup = true,     -- Auto-setup for markdown files
            auto_add_to_sources = true, -- Automatically add to nvim-cmp sources
        },
        blink_cmp = {
            enabled = true,
            priority = 100,
            max_item_count = 25,
        },
    },
    enable_tags = true,
    tag_highlight = "Special",
    auto_setup_keymaps = true,
})

-- 3. PERFORMANCE SETUP (optimized for speed)
require('pebble').setup({
    completion = {
        enabled = true,
        cache_ttl = 60000, -- 1 minute cache
        cache_max_size = 1000,
        nvim_cmp = {
            enabled = true,
            priority = 150,
            max_item_count = 15, -- Fewer items for better performance
            filetype_setup = true,
            auto_add_to_sources = false, -- Manual setup for better control
        },
        blink_cmp = { enabled = false }, -- Disable to avoid conflicts
    },
})

-- 4. DEBUG SETUP (for troubleshooting)
require('pebble').setup({
    completion = {
        enabled = true,
        debug = true, -- Enable debug logging
        prevent_conflicts = false,
        nvim_cmp = {
            enabled = true,
            debug = true,
            max_item_count = 50,
            filetype_setup = true,
            auto_add_to_sources = true,
        },
    },
})

-- nvim-cmp configuration examples (choose one approach)

-- APPROACH 1: Automatic setup (recommended)
-- Pebble will automatically add itself to markdown files when using:
-- completion.nvim_cmp.auto_add_to_sources = true (default)

local cmp = require('cmp')
cmp.setup({
    sources = cmp.config.sources({
        { name = 'nvim_lsp' },
        { name = 'buffer' },
        { name = 'path' },
        -- No need to add 'pebble' here - it's added automatically for markdown files
    }),
    
    mapping = cmp.mapping.preset.insert({
        ['<C-Space>'] = cmp.mapping.complete(),
        ['<CR>'] = cmp.mapping.confirm({ select = true }),
        ['<Tab>'] = cmp.mapping.select_next_item(),
        ['<S-Tab>'] = cmp.mapping.select_prev_item(),
    }),
})

-- APPROACH 2: Manual setup (for fine control)
-- Use this if you set completion.nvim_cmp.auto_add_to_sources = false

--[[
local cmp = require('cmp')

-- Global setup
cmp.setup({
    sources = cmp.config.sources({
        { name = 'nvim_lsp' },
        { name = 'buffer' },
        { name = 'path' },
    }),
    mapping = cmp.mapping.preset.insert({
        ['<C-Space>'] = cmp.mapping.complete(),
        ['<CR>'] = cmp.mapping.confirm({ select = true }),
        ['<Tab>'] = cmp.mapping.select_next_item(),
        ['<S-Tab>'] = cmp.mapping.select_prev_item(),
    }),
})

-- Markdown-specific setup
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "markdown", "md" },
    callback = function()
        cmp.setup.buffer({
            sources = cmp.config.sources({
                { name = 'pebble', priority = 100 }, -- Add pebble for markdown files
                { name = 'nvim_lsp' },
                { name = 'buffer' },
                { name = 'path' },
            })
        })
    end,
})
--]]

-- Troubleshooting and testing commands
vim.keymap.set('n', '<leader>pcs', ':PebbleCompletionStatus<CR>', 
    { desc = 'Show completion status and configuration' })

vim.keymap.set('n', '<leader>pcv', ':PebbleValidateSetup<CR>', 
    { desc = 'Validate pebble completion setup' })

vim.keymap.set('n', '<leader>pct', ':PebbleTestCompletion<CR>', 
    { desc = 'Test completion functionality' })

vim.keymap.set('n', '<leader>pcr', ':PebbleRefreshCache<CR>', 
    { desc = 'Refresh completion cache' })

vim.keymap.set('n', '<leader>pcw', ':PebbleCompletionWizard<CR>', 
    { desc = 'Run interactive setup wizard' })

-- Show available configuration presets
vim.keymap.set('n', '<leader>pcp', ':PebbleConfigPreset<CR>', 
    { desc = 'List configuration presets' })

-- Enhanced Telescope integration for browsing notes
vim.keymap.set('n', '<leader>fn', function()
    local completion = require('pebble.completion')
    local root_dir = completion.get_root_dir()
    local completions = completion.get_wiki_completions('', root_dir)
    
    if #completions == 0 then
        vim.notify('No markdown notes found. Check your workspace or run :PebbleValidateSetup', vim.log.levels.WARN)
        return
    end
    
    local telescope_ok, telescope = pcall(require, 'telescope')
    if not telescope_ok then
        vim.notify('Telescope not available. Install telescope.nvim for this feature', vim.log.levels.WARN)
        return
    end
    
    require('telescope.pickers').new({}, {
        prompt_title = 'Wiki Notes (' .. #completions .. ' found)',
        finder = require('telescope.finders').new_table({
            results = completions,
            entry_maker = function(entry)
                local file_path = entry.note_metadata and entry.note_metadata.file_path or entry.file_path
                return {
                    value = file_path,
                    display = string.format('%s (%s)', entry.label, entry.detail or 'no detail'),
                    ordinal = entry.label,
                    path = file_path,
                }
            end,
        }),
        sorter = require('telescope.config').values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            require('telescope.actions').select_default:replace(function()
                require('telescope.actions').close(prompt_bufnr)
                local selection = require('telescope.actions.state').get_selected_entry()
                if selection and selection.value then
                    vim.cmd('edit ' .. vim.fn.fnameescape(selection.value))
                else
                    vim.notify('Invalid selection', vim.log.levels.WARN)
                end
            end)
            return true
        end,
    }):find()
end, { desc = 'Browse all wiki notes' })

-- Optional: Enhanced auto-trigger for wiki link completion
vim.api.nvim_create_autocmd('InsertCharPre', {
    pattern = '*.md',
    callback = function()
        if vim.v.char == '[' then
            local line = vim.api.nvim_get_current_line()
            local col = vim.api.nvim_win_get_cursor(0)[2]
            
            -- Check if we're typing the second [ for [[
            if col > 0 and line:sub(col, col) == '[' then
                vim.schedule(function()
                    -- Auto-trigger completion after a short delay
                    local cmp_ok, cmp = pcall(require, 'cmp')
                    if cmp_ok and vim.bo.filetype == 'markdown' then
                        cmp.complete()
                    end
                end)
            end
        elseif vim.v.char == '(' then
            -- Also trigger on ]( for markdown links
            local line = vim.api.nvim_get_current_line()
            local col = vim.api.nvim_win_get_cursor(0)[2]
            
            if col > 0 and line:sub(col, col) == ']' then
                vim.schedule(function()
                    local cmp_ok, cmp = pcall(require, 'cmp')
                    if cmp_ok and vim.bo.filetype == 'markdown' then
                        cmp.complete()
                    end
                end)
            end
        end
    end,
})

-- Optional: Create a command to insert a wiki link for the current word
vim.api.nvim_create_user_command('WikiLink', function()
    local word = vim.fn.expand('<cword>')
    if word == '' then
        vim.notify('No word under cursor', vim.log.levels.WARN)
        return
    end
    
    -- Replace the word with [[word]]
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    
    -- Find word boundaries
    local start_col = col
    while start_col > 0 and line:sub(start_col, start_col):match('%w') do
        start_col = start_col - 1
    end
    start_col = start_col + 1
    
    local end_col = col + 1
    while end_col <= #line and line:sub(end_col, end_col):match('%w') do
        end_col = end_col + 1
    end
    end_col = end_col - 1
    
    local new_line = line:sub(1, start_col - 1) .. '[[' .. word .. ']]' .. line:sub(end_col + 1)
    vim.api.nvim_set_current_line(new_line)
    
    -- Position cursor after the ]]
    vim.api.nvim_win_set_cursor(0, {vim.api.nvim_win_get_cursor(0)[1], start_col + #word + 3})
end, { desc = 'Convert current word to wiki link' })

vim.keymap.set('n', '<leader>mw', ':WikiLink<CR>', 
    { desc = 'Convert word to wiki link' })

-- Additional helpful commands for troubleshooting
vim.keymap.set('n', '<leader>pd', ':PebbleDiagnose<CR>', 
    { desc = 'Run pebble diagnostics' })

vim.keymap.set('n', '<leader>pr', ':PebbleReset<CR>', 
    { desc = 'Reset all pebble caches' })
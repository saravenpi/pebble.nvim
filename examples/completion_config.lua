-- Example configuration for pebble.nvim wiki link completion

-- Basic pebble setup with completion enabled
require('pebble').setup({
    completion = true,  -- Enable completion (default)
    
    -- Optional: customize completion behavior
    -- completion = {
    --     nvim_cmp = true,   -- Enable nvim-cmp source (default: true if available)
    --     blink_cmp = true,  -- Enable blink.cmp source (default: true if available)
    -- },
    
    -- Other pebble settings...
    enable_tags = true,
    tag_highlight = "Special",
    auto_setup_keymaps = true,
})

-- nvim-cmp configuration example
local cmp = require('cmp')
cmp.setup({
    sources = cmp.config.sources({
        { name = 'nvim_lsp' },
        { name = 'pebble_wiki_links' },  -- Add pebble wiki link completion
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

-- Optional: Custom keymaps for completion testing
vim.keymap.set('n', '<leader>mc', ':PebbleComplete<CR>', 
    { desc = 'Test wiki link completion' })

vim.keymap.set('n', '<leader>mr', ':PebbleCompletionRefresh<CR>', 
    { desc = 'Refresh completion cache' })

vim.keymap.set('n', '<leader>ms', ':PebbleCompletionStats<CR>', 
    { desc = 'Show completion stats' })

-- Optional: Telescope integration for browsing notes
vim.keymap.set('n', '<leader>fn', function()
    local completion = require('pebble.completion')
    local root_dir = completion.get_root_dir()
    local completions = completion.get_wiki_completions('', root_dir)
    
    if #completions == 0 then
        vim.notify('No markdown notes found', vim.log.levels.WARN)
        return
    end
    
    require('telescope.pickers').new({}, {
        prompt_title = 'Wiki Notes (' .. #completions .. ' found)',
        finder = require('telescope.finders').new_table({
            results = completions,
            entry_maker = function(entry)
                return {
                    value = entry.note_metadata.file_path,
                    display = string.format('%s (%s)', entry.label, entry.detail),
                    ordinal = entry.label,
                    path = entry.note_metadata.file_path,
                }
            end,
        }),
        sorter = require('telescope.config').values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            require('telescope.actions').select_default:replace(function()
                require('telescope.actions').close(prompt_bufnr)
                local selection = require('telescope.actions.state').get_selected_entry()
                if selection then
                    vim.cmd('edit ' .. vim.fn.fnameescape(selection.value))
                end
            end)
            return true
        end,
    }):find()
end, { desc = 'Browse all wiki notes' })

-- Optional: Auto-complete wiki links when typing [[
vim.api.nvim_create_autocmd('InsertCharPre', {
    pattern = '*.md',
    callback = function()
        if vim.v.char == '[' then
            local line = vim.api.nvim_get_current_line()
            local col = vim.api.nvim_win_get_cursor(0)[2]
            
            -- Check if we just typed the first [ and are about to type the second [
            if col > 0 and line:sub(col, col) == '[' then
                -- We're typing the second [, which will trigger completion
                -- You can add custom logic here if needed
                vim.schedule(function()
                    -- Optional: automatically trigger completion after typing [[
                    -- require('cmp').complete()
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
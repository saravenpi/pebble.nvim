-- Optimal Pebble.nvim Configuration
-- ==================================
-- This configuration provides the best performance and user experience
-- for pebble.nvim with all completion fixes integrated.

-- ===============================
-- BASIC SETUP (Recommended)
-- ===============================

require('pebble').setup({
    -- Core Features
    enable_tags = true,                    -- Enable #hashtag highlighting
    tag_highlight = "Special",             -- Highlight color for tags
    auto_setup_keymaps = true,             -- Automatic keymap setup
    
    -- Performance Optimization
    search = {
        ripgrep_path = "rg",               -- Path to ripgrep binary
        max_files = 2000,                  -- Maximum files to process
        max_depth = 10,                    -- Directory search depth
        timeout = 30000,                   -- Search timeout (30s)
    },
    
    -- Completion System
    completion = {
        nvim_cmp = true,                   -- Enable nvim-cmp integration
        blink_cmp = true,                  -- Enable blink.cmp integration
        tags = {
            -- Tag completion settings
            async_extraction = true,        -- Async tag extraction for performance
            cache_ttl = 60000,             -- 1-minute cache TTL
            max_completion_items = 50,      -- Limit completion results
            fuzzy_matching = true,          -- Enable fuzzy matching
            nested_tag_support = true,      -- Support nested tags like #work/project
        }
    },
    
    -- Global keymaps (optional - set to true if you want them)
    global_keymaps = false,
})

-- ===============================
-- NVIM-CMP INTEGRATION
-- ===============================

-- If you're using nvim-cmp, add pebble sources to your config
local cmp = require('cmp')
cmp.setup({
    sources = cmp.config.sources({
        { name = 'nvim_lsp', priority = 1000 },
        { name = 'pebble', priority = 900 },        -- Wiki links and file completion
        { name = 'pebble_tags', priority = 800 },   -- Tag completion
    }, {
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

-- ===============================
-- BLINK.CMP INTEGRATION
-- ===============================

-- If you're using blink.cmp instead of nvim-cmp
local blink = require('blink.cmp')
blink.setup({
    sources = {
        providers = {
            pebble = { name = 'pebble', module = 'pebble.completion.blink_cmp' },
            pebble_tags = { name = 'pebble_tags', module = 'pebble.completion.tags' },
        },
        cmdline = {},
    }
})

-- ===============================
-- ADVANCED CONFIGURATION
-- ===============================

-- Performance monitoring commands
vim.keymap.set('n', '<leader>mps', ':PebbleStats<CR>', { desc = 'Show pebble performance stats' })
vim.keymap.set('n', '<leader>mpc', ':PebbleCompletionStats<CR>', { desc = 'Show completion stats' })
vim.keymap.set('n', '<leader>mpr', ':PebbleCompletionRefresh<CR>', { desc = 'Refresh completion cache' })

-- Tag completion trigger (manual)
vim.keymap.set('i', '<C-t><C-t>', function()
    local tags = require('pebble.completion.tags')
    tags.trigger_completion()
end, { desc = 'Trigger tag completion' })

-- ===============================
-- PERFORMANCE VALIDATION
-- ===============================

-- Auto-validate performance on startup
vim.api.nvim_create_autocmd('VimEnter', {
    callback = function()
        -- Check ripgrep availability
        local search = require('pebble.bases.search')
        if not search.has_ripgrep() then
            vim.notify(
                'Pebble.nvim: Install ripgrep for optimal performance:\n' ..
                'macOS: brew install ripgrep\n' ..
                'Ubuntu: apt install ripgrep\n' ..
                'Arch: pacman -S ripgrep',
                vim.log.levels.WARN
            )
        end
        
        -- Validate large repository performance
        vim.defer_fn(function()
            local files = search.find_markdown_files_sync(vim.fn.getcwd())
            local file_count = #files
            
            if file_count > 1000 then
                vim.notify(
                    string.format('Pebble.nvim: Large repository detected (%d files)\n' ..
                    'Consider using :PebbleStats to monitor performance', file_count),
                    vim.log.levels.INFO
                )
            end
        end, 2000)
    end
})

-- ===============================
-- TELESCOPE INTEGRATION
-- ===============================

-- Enhanced note browsing with telescope
if pcall(require, 'telescope') then
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
end

-- ===============================
-- HEALTH CHECK COMMAND
-- ===============================

vim.api.nvim_create_user_command('PebbleHealth', function()
    print('🚀 Pebble.nvim Health Check')
    print('============================')
    
    -- Check ripgrep
    local search = require('pebble.bases.search')
    local rg_version = search.get_ripgrep_version()
    if rg_version then
        print('✅ Ripgrep: v' .. rg_version)
    else
        print('❌ Ripgrep: Not found')
    end
    
    -- Check completion engines
    local nvim_cmp = require('pebble.completion.nvim_cmp')
    if nvim_cmp.is_available() then
        print('✅ nvim-cmp: Available')
    else
        print('⚠️  nvim-cmp: Not available')
    end
    
    local blink_cmp = require('pebble.completion.blink_cmp')
    if blink_cmp.is_available() then
        print('✅ blink.cmp: Available')
    else
        print('⚠️  blink.cmp: Not available')
    end
    
    -- Check performance
    local files = search.find_markdown_files_sync(vim.fn.getcwd())
    local file_count = #files
    
    print(string.format('📁 Repository: %d markdown files', file_count))
    
    if file_count > 1000 then
        print('⚠️  Large repository - monitor performance')
    else
        print('✅ Repository size: Optimal')
    end
    
    -- Check cache status
    local completion = require('pebble.completion')
    local stats = completion.get_stats()
    if stats.cache_size then
        print(string.format('📊 Completion cache: %d files, %.1fs age', 
            stats.cache_size, stats.cache_age / 1000))
    end
    
    local tags = require('pebble.completion.tags')
    local tag_stats = tags.get_cache_stats()
    print(string.format('🏷️  Tag cache: %d entries, valid: %s', 
        tag_stats.entries_count or 0, tostring(tag_stats.is_valid)))
end, { desc = 'Run pebble.nvim health check' })

-- ===============================
-- MIGRATION HELPERS
-- ===============================

-- Command to migrate from old pebble configuration
vim.api.nvim_create_user_command('PebbleMigrate', function()
    print('🔄 Pebble.nvim Migration Guide')
    print('==============================')
    print('New features in this version:')
    print('• Tag completion with #hashtags')
    print('• Improved search performance with ripgrep')
    print('• Enhanced wiki link completion')
    print('• Better caching and async operations')
    print('')
    print('No breaking changes - your existing config should work!')
    print('Run :PebbleHealth to validate your setup.')
end, { desc = 'Show migration guide' })

-- ===============================
-- EXAMPLE WORKFLOW COMMANDS
-- ===============================

-- Quick note creation
vim.api.nvim_create_user_command('NewNote', function(opts)
    local title = opts.args
    if title == '' then
        title = vim.fn.input('Note title: ')
    end
    
    if title == '' then
        vim.notify('Note title required', vim.log.levels.WARN)
        return
    end
    
    -- Create filename from title
    local filename = title:gsub('%s+', '_'):gsub('[^%w_-]', ''):lower()
    local filepath = vim.fn.expand('%:p:h') .. '/' .. filename .. '.md'
    
    -- Create note with YAML frontmatter
    local content = {
        '---',
        'title: "' .. title .. '"',
        'created: ' .. os.date('%Y-%m-%d'),
        'tags: []',
        '---',
        '',
        '# ' .. title,
        '',
        ''
    }
    
    vim.fn.writefile(content, filepath)
    vim.cmd('edit ' .. vim.fn.fnameescape(filepath))
    
    -- Position cursor at end
    vim.api.nvim_win_set_cursor(0, {#content, 0})
    
    vim.notify('Created note: ' .. filename .. '.md', vim.log.levels.INFO)
end, { nargs = '?', desc = 'Create new note with YAML frontmatter' })

vim.keymap.set('n', '<leader>mn', ':NewNote<CR>', { desc = 'Create new note' })

return {
    -- Export configuration for other files to use
    optimal_config = true,
    version = '2.0',
    features = {
        'ripgrep_optimization',
        'tag_completion',
        'wiki_link_completion',
        'performance_monitoring',
        'async_operations'
    }
}
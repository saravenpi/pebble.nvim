local M = {}

local tags = require("pebble.completion.tags")

-- Setup completion integration
function M.setup(config)
    config = config or {}
    
    -- Initialize tag completion
    tags.setup(config.tags or {})
    
    -- Auto-detect and register with completion engines
    M.register_completion_sources(config)
    
    -- Setup manual completion trigger
    if config.manual_trigger_key then
        vim.keymap.set("i", config.manual_trigger_key, function()
            tags.trigger_completion()
        end, { desc = "Trigger tag completion" })
    end
end

-- Register completion sources with available engines
function M.register_completion_sources(config)
    -- Try to register with nvim-cmp
    local cmp_ok, cmp = pcall(require, 'cmp')
    if cmp_ok then
        M.register_nvim_cmp()
        vim.notify("Pebble tags: Registered with nvim-cmp", vim.log.levels.INFO)
    end
    
    -- Try to register with blink.cmp
    local blink_ok, blink = pcall(require, 'blink.cmp')
    if blink_ok then
        M.register_blink_cmp()
        vim.notify("Pebble tags: Registered with blink.cmp", vim.log.levels.INFO)
    end
    
    if not (cmp_ok or blink_ok) then
        vim.notify("Pebble tags: No compatible completion engine found. Install nvim-cmp or blink.cmp", vim.log.levels.WARN)
    end
end

-- Register with nvim-cmp
function M.register_nvim_cmp()
    local cmp_ok, cmp = pcall(require, 'cmp')
    if not cmp_ok then
        return false
    end
    
    -- Register the source
    cmp.register_source('pebble_tags', tags.get_completion_source())
    
    -- Auto-add to sources for markdown files
    vim.api.nvim_create_autocmd("FileType", {
        pattern = {"markdown", "md"},
        callback = function()
            local current_sources = cmp.get_config().sources or {}
            
            -- Check if our source is already added
            local already_added = false
            for _, source_group in ipairs(current_sources) do
                for _, source in ipairs(source_group) do
                    if source.name == 'pebble_tags' then
                        already_added = true
                        break
                    end
                end
                if already_added then break end
            end
            
            -- Add our source if not already present
            if not already_added then
                table.insert(current_sources, {{ name = 'pebble_tags' }})
                cmp.setup.buffer({
                    sources = current_sources
                })
            end
        end
    })
    
    return true
end

-- Register with blink.cmp
function M.register_blink_cmp()
    local blink_ok, blink = pcall(require, 'blink.cmp')
    if not blink_ok then
        return false
    end
    
    -- Register the source with blink.cmp
    blink.add_source('pebble_tags', tags.get_blink_source())
    
    return true
end

-- Omnifunc for manual completion (fallback)
function M.omnifunc(findstart, base)
    if findstart == 1 then
        -- Find start of tag
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]
        
        local before_cursor = line:sub(1, col + 1)
        local hash_pos = before_cursor:reverse():find("#")
        
        if hash_pos then
            return col + 1 - hash_pos
        else
            return -3  -- Cancel completion
        end
    else
        -- Return completions
        tags.setup({}) -- Ensure initialized
        return tags.get_completion_items(base)
    end
end

-- Get completion statistics
function M.get_stats()
    return {
        tags = tags.get_cache_stats(),
    }
end

-- Manual cache refresh
function M.refresh_cache()
    tags.refresh_cache()
end

return M
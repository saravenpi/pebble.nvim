local M = {}

local tags = require("pebble.completion.tags")

-- Setup completion integration
function M.setup(config)
    config = config or {}
    
    -- Initialize tag completion first
    tags.setup(config.tags or {})
    
    -- Auto-detect and register with completion engines
    M.register_completion_sources(config)
    
    -- Setup manual completion trigger
    if config.manual_trigger_key then
        vim.keymap.set("i", config.manual_trigger_key, function()
            tags.trigger_completion()
        end, { desc = "Trigger tag completion" })
    end
    
    -- Setup automatic completion trigger for # character
    vim.api.nvim_create_autocmd("FileType", {
        pattern = {"markdown", "md", "mdx"},
        callback = function()
            -- Set up buffer-local completion for tags
            vim.keymap.set("i", "#", function()
                vim.api.nvim_feedkeys("#", "n", false)
                -- Trigger completion after a short delay
                vim.defer_fn(function()
                    if vim.fn.pumvisible() == 0 then -- Only if completion menu isn't already open
                        tags.trigger_completion()
                    end
                end, 50)
            end, { buffer = true, desc = "Insert # and trigger tag completion" })
        end
    })
end

-- Register completion sources with available engines
function M.register_completion_sources(config)
    local registered_engines = {}
    
    -- Try to register with nvim-cmp
    if M.register_nvim_cmp(config) then
        table.insert(registered_engines, "nvim-cmp")
    end
    
    -- Try to register with blink.cmp
    if M.register_blink_cmp(config) then
        table.insert(registered_engines, "blink.cmp")
    end
    
    if #registered_engines > 0 then
        vim.notify("Pebble tags: Registered with " .. table.concat(registered_engines, ", "), vim.log.levels.INFO)
    else
        vim.notify("Pebble tags: No compatible completion engine found. Install nvim-cmp or blink.cmp", vim.log.levels.WARN)
    end
end

-- Register with nvim-cmp
function M.register_nvim_cmp(config)
    local cmp_ok, cmp = pcall(require, 'cmp')
    if not cmp_ok then
        return false
    end
    
    -- Register the source
    cmp.register_source('pebble_tags', tags.get_completion_source())
    
    -- Auto-add to sources for markdown files with improved logic
    vim.api.nvim_create_autocmd("FileType", {
        pattern = {"markdown", "md", "mdx"},
        callback = function()
            -- Get current buffer config
            local buf_config = cmp.get_config()
            local current_sources = buf_config and buf_config.sources or cmp.get_config().sources or {}
            
            -- Check if our source is already added
            local already_added = false
            for _, source_group in ipairs(current_sources) do
                if type(source_group) == "table" then
                    for _, source in ipairs(source_group) do
                        if type(source) == "table" and source.name == 'pebble_tags' then
                            already_added = true
                            break
                        end
                    end
                end
                if already_added then break end
            end
            
            -- Add our source if not already present
            if not already_added then
                -- Clone current sources to avoid modifying the original
                local new_sources = vim.deepcopy(current_sources)
                
                -- Add pebble_tags as a high-priority source
                table.insert(new_sources, 1, { 
                    { name = 'pebble_tags', priority = 1000 }
                })
                
                cmp.setup.buffer({
                    sources = new_sources
                })
            end
        end
    })
    
    return true
end

-- Register with blink.cmp
function M.register_blink_cmp(config)
    local blink_ok, blink = pcall(require, 'blink.cmp')
    if not blink_ok then
        return false
    end
    
    -- Try different registration methods for blink.cmp
    local source = tags.get_blink_source()
    
    -- Method 1: Modern blink.cmp API
    if blink.register_source then
        local success, err = pcall(blink.register_source, 'pebble_tags', source)
        if success then
            return true
        else
            vim.notify("Failed to register with blink.cmp using register_source: " .. tostring(err), vim.log.levels.DEBUG)
        end
    end
    
    -- Method 2: Via sources module
    local sources_ok, sources = pcall(require, 'blink.cmp.sources')
    if sources_ok and sources.register then
        local success, err = pcall(sources.register, 'pebble_tags', source)
        if success then
            return true
        else
            vim.notify("Failed to register with blink.cmp using sources.register: " .. tostring(err), vim.log.levels.DEBUG)
        end
    end
    
    -- Method 3: Manual addition to config (fallback)
    local config_ok, blink_config = pcall(require, 'blink.cmp.config')
    if config_ok and blink_config.sources then
        blink_config.sources.pebble_tags = source
        return true
    end
    
    return false
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
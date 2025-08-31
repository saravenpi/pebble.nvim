local M = {}

-- DEPRECATED: This file is now a wrapper for the new completion manager
-- Direct users to the new system
local function redirect_to_manager()
	local ok, manager = pcall(require, "pebble.completion.manager")
	if not ok then
		vim.notify("Pebble completion manager not found", vim.log.levels.ERROR)
		return nil
	end
	return manager
end

-- Setup completion integration using new manager
function M.setup(config)
    config = config or {}
    
    -- Warn about deprecated usage
    vim.notify(
    	"pebble.completion.init is deprecated. Use require('pebble').setup() with completion config instead.",
    	vim.log.levels.WARN
    )
    
    local manager = redirect_to_manager()
    if not manager then
    	return false
    end
    
    -- Convert old config format to new manager format
    local manager_config = {
    	enabled = config.enabled ~= false,
    	nvim_cmp = {
    		enabled = config.nvim_cmp ~= false,
    		priority = (config.nvim_cmp and config.nvim_cmp.priority) or 100,
    		max_item_count = (config.nvim_cmp and config.nvim_cmp.max_item_count) or 50,
    	},
    	blink_cmp = {
    		enabled = config.blink_cmp ~= false,
    		priority = (config.blink_cmp and config.blink_cmp.priority) or 100,
    		max_item_count = (config.blink_cmp and config.blink_cmp.max_item_count) or 50,
    	},
    	debug = config.debug or false,
    }
    
    -- Initialize the new manager
    manager.setup(manager_config)
    return manager.register_all_sources()
end

-- Deprecated methods - redirect to manager
function M.register_completion_sources(config)
	local manager = redirect_to_manager()
	if not manager then
		return false
	end
	
	return manager.register_all_sources()
end

function M.register_nvim_cmp(config)
	local manager = redirect_to_manager()
	if not manager then
		return false
	end
	
	return manager.register_nvim_cmp(config or {})
end

function M.register_blink_cmp(config)
	local manager = redirect_to_manager()
	if not manager then
		return false
	end
	
	return manager.register_blink_cmp(config or {})
end

-- Redirect legacy methods to new manager
function M.omnifunc(findstart, base)
	-- Keep legacy omnifunc for backward compatibility
	local ok, tags = pcall(require, "pebble.completion.tags")
	if not ok then
		return findstart == 1 and -3 or {}
	end
	
    if findstart == 1 then
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]
        
        local before_cursor = line:sub(1, col + 1)
        local hash_pos = before_cursor:reverse():find("#")
        
        if hash_pos then
            return col + 1 - hash_pos
        else
            return -3
        end
    else
        tags.setup({})
        return tags.get_completion_items(base)
    end
end

function M.get_stats()
	local manager = redirect_to_manager()
	if not manager then
		return {}
	end
	
	return manager.get_status()
end

function M.refresh_cache()
	local manager = redirect_to_manager()
	if not manager then
		return false
	end
	
	return manager.refresh_cache()
end

return M
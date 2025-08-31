-- Legacy cmp_source.lua - DEPRECATED
-- This file is kept for backward compatibility only.
-- New completion system is in lua/pebble/completion/

-- Redirect to the new completion system
local M = {}

-- Warn about deprecated usage
vim.notify(
	"pebble.cmp_source is deprecated. Use require('pebble.completion.manager') instead.",
	vim.log.levels.WARN
)

-- Provide backward compatibility by redirecting to new system
function M.new()
	-- Try to use the new system
	local ok, manager = pcall(require, "pebble.completion.manager")
	if ok then
		-- Setup with default options if not already initialized
		manager.setup({})
		manager.register_all_sources()
	end
	
	-- Return empty source for compatibility
	return {
		is_available = function() return false end,
		get_debug_name = function() return "pebble_deprecated" end,
		complete = function(_, callback) callback({ items = {}, isIncomplete = false }) end
	}
end

return M
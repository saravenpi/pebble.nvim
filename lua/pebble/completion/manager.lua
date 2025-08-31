-- Completion Manager - Unified completion source registration
local M = {}

local registered_sources = {}
local completion = require("pebble.completion")

-- Configuration defaults
local DEFAULT_CONFIG = {
	enabled = true,
	nvim_cmp = {
		enabled = true,
		priority = 100,
		max_item_count = 50,
		trigger_characters = { "[", "(" },
		keyword_length = 0,
	},
	blink_cmp = {
		enabled = true,
		priority = 100,
		max_item_count = 50,
		trigger_characters = { "[", "(" },
	},
	cache_ttl = 30000, -- 30 seconds
	cache_max_size = 2000,
	debug = false,
}

-- Internal state
local manager_config = {}
local is_initialized = false

-- Debug logging
local function debug_log(msg)
	if manager_config.debug then
		vim.notify("[Pebble Completion] " .. msg, vim.log.levels.DEBUG)
	end
end

-- Setup the completion manager
function M.setup(config)
	config = config or {}
	manager_config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config)
	
	debug_log("Initializing completion manager")
	
	-- Initialize base completion system
	completion.setup({
		cache_ttl = manager_config.cache_ttl,
		cache_max_size = manager_config.cache_max_size,
	})
	
	is_initialized = true
	return true
end

-- Register all available completion sources
function M.register_all_sources()
	if not is_initialized then
		vim.notify("Pebble completion manager not initialized. Call setup() first.", vim.log.levels.ERROR)
		return false
	end
	
	if not manager_config.enabled then
		debug_log("Completion disabled in config")
		return true
	end
	
	local success_count = 0
	local total_sources = 0
	
	-- Try to register nvim-cmp source
	if manager_config.nvim_cmp and manager_config.nvim_cmp.enabled then
		total_sources = total_sources + 1
		local ok, result = M.register_nvim_cmp(manager_config.nvim_cmp)
		if ok and result then
			success_count = success_count + 1
			debug_log("Successfully registered nvim-cmp source")
		else
			debug_log("Failed to register nvim-cmp source: " .. (result or "unknown error"))
		end
	end
	
	-- Try to register blink.cmp source
	if manager_config.blink_cmp and manager_config.blink_cmp.enabled then
		total_sources = total_sources + 1
		local ok, result = M.register_blink_cmp(manager_config.blink_cmp)
		if ok and result then
			success_count = success_count + 1
			debug_log("Successfully registered blink.cmp source")
		else
			debug_log("Failed to register blink.cmp source: " .. (result or "unknown error"))
		end
	end
	
	-- Setup cache invalidation
	M.setup_cache_invalidation()
	
	-- Log results
	if success_count > 0 then
		local message = string.format("Registered %d/%d completion sources successfully", success_count, total_sources)
		vim.notify("Pebble: " .. message, vim.log.levels.INFO)
	elseif total_sources > 0 then
		vim.notify("Pebble: Failed to register any completion sources. Check that nvim-cmp or blink.cmp is installed.", vim.log.levels.WARN)
	else
		debug_log("No completion sources enabled in config")
	end
	
	return success_count > 0
end

-- Register nvim-cmp source
function M.register_nvim_cmp(opts)
	opts = opts or {}
	
	local ok, nvim_cmp_module = pcall(require, "pebble.completion.nvim_cmp")
	if not ok then
		return false, "nvim-cmp completion module not found"
	end
	
	if not nvim_cmp_module.is_available() then
		return false, "nvim-cmp not installed or available"
	end
	
	local success, err = pcall(nvim_cmp_module.register, opts)
	if success then
		registered_sources.nvim_cmp = true
		return true, "registered"
	else
		return false, err or "registration failed"
	end
end

-- Register blink.cmp source
function M.register_blink_cmp(opts)
	opts = opts or {}
	
	local ok, blink_cmp_module = pcall(require, "pebble.completion.blink_cmp")
	if not ok then
		return false, "blink.cmp completion module not found"
	end
	
	if not blink_cmp_module.is_available() then
		return false, "blink.cmp not installed or available"
	end
	
	local success, err = pcall(blink_cmp_module.register, opts)
	if success then
		registered_sources.blink_cmp = true
		return true, "registered"
	else
		return false, err or "registration failed"
	end
end

-- Setup automatic cache invalidation
function M.setup_cache_invalidation()
	-- Invalidate cache when files change
	vim.api.nvim_create_autocmd({ "BufWritePost", "BufNewFile", "BufDelete" }, {
		pattern = "*.md",
		callback = function()
			completion.invalidate_cache()
			debug_log("Cache invalidated due to file change")
		end,
		group = vim.api.nvim_create_augroup("PebbleCompletionCacheInvalidation", { clear = true })
	})
end

-- Get manager status and statistics
function M.get_status()
	local completion_stats = completion.get_stats()
	
	return {
		initialized = is_initialized,
		config = manager_config,
		registered_sources = registered_sources,
		completion_stats = completion_stats,
		available_engines = {
			nvim_cmp = pcall(require, "cmp") and true or false,
			blink_cmp = pcall(require, "blink.cmp") and true or false,
		}
	}
end

-- Manual cache refresh
function M.refresh_cache()
	completion.invalidate_cache()
	debug_log("Manual cache refresh triggered")
	return true
end

-- Test completion functionality
function M.test_completion()
	local is_wiki, wiki_query = completion.is_wiki_link_context()
	local is_markdown, markdown_query = completion.is_markdown_link_context()
	
	local results = {}
	
	if is_wiki then
		local root_dir = completion.get_root_dir()
		local completions = completion.get_wiki_completions(wiki_query, root_dir)
		results.wiki_links = {
			query = wiki_query,
			count = #completions,
			items = vim.tbl_map(function(item) return item.label end, vim.list_slice(completions, 1, 5))
		}
	elseif is_markdown then
		local root_dir = completion.get_root_dir()
		local completions = completion.get_markdown_link_completions(markdown_query, root_dir)
		results.markdown_links = {
			query = markdown_query,
			count = #completions,
			items = vim.tbl_map(function(item) return item.label end, vim.list_slice(completions, 1, 5))
		}
	else
		results.error = "Not in a link context. Position cursor after [[ or ]( to test."
	end
	
	return results
end

-- Create completion testing command
function M.setup_commands()
	-- Test completion functionality
	vim.api.nvim_create_user_command("PebbleTestCompletion", function()
		local results = M.test_completion()
		
		if results.error then
			vim.notify(results.error, vim.log.levels.WARN)
		elseif results.wiki_links then
			vim.notify(string.format(
				"Wiki Link Test Results:\nQuery: '%s'\nFound: %d items\nSample: %s",
				results.wiki_links.query,
				results.wiki_links.count,
				table.concat(results.wiki_links.items, ", ")
			), vim.log.levels.INFO)
		elseif results.markdown_links then
			vim.notify(string.format(
				"Markdown Link Test Results:\nQuery: '%s'\nFound: %d items\nSample: %s",
				results.markdown_links.query,
				results.markdown_links.count,
				table.concat(results.markdown_links.items, ", ")
			), vim.log.levels.INFO)
		end
	end, { desc = "Test Pebble completion functionality" })
	
	-- Show status
	vim.api.nvim_create_user_command("PebbleCompletionStatus", function()
		local status = M.get_status()
		local lines = {
			"=== Pebble Completion Status ===",
			"Initialized: " .. tostring(status.initialized),
			"Sources registered: " .. vim.inspect(status.registered_sources),
			"Available engines: " .. vim.inspect(status.available_engines),
			"",
			"Cache stats:",
			"  Valid: " .. tostring(status.completion_stats.cache_valid),
			"  Size: " .. status.completion_stats.cache_size .. " notes",
			"  Age: " .. math.floor(status.completion_stats.cache_age / 1000) .. " seconds",
			"  TTL: " .. math.floor(status.completion_stats.cache_ttl / 1000) .. " seconds",
		}
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
	end, { desc = "Show Pebble completion status" })
	
	-- Refresh cache
	vim.api.nvim_create_user_command("PebbleRefreshCache", function()
		M.refresh_cache()
		vim.notify("Pebble completion cache refreshed", vim.log.levels.INFO)
	end, { desc = "Refresh Pebble completion cache" })
end

return M
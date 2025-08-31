-- Completion Manager - Unified completion source registration
local M = {}

local registered_sources = {}
-- Use utils module to avoid circular dependencies
local utils

-- Configuration defaults
local DEFAULT_CONFIG = {
	enabled = true,
	nvim_cmp = {
		enabled = true,
		priority = 100,
		max_item_count = 50,
		trigger_characters = { "[", "(", "#" },
		keyword_length = 0,
		filetype_setup = true, -- Enable filetype-specific buffer setup
		auto_add_to_sources = true, -- Automatically add to buffer sources for markdown
		debug = false,
	},
	blink_cmp = {
		enabled = true,
		priority = 100,
		max_item_count = 50,
		trigger_characters = { "[", "(", "#" },
		debug = false,
	},
	cache_ttl = 30000, -- 30 seconds
	cache_max_size = 2000,
	debug = false,
	prevent_conflicts = true, -- Prevent registering if already registered
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
	
	-- Handle boolean config values by converting to table format
	local normalized_config = {}
	for key, value in pairs(config) do
		if key == "nvim_cmp" or key == "blink_cmp" then
			if type(value) == "boolean" then
				normalized_config[key] = { enabled = value }
			elseif type(value) == "table" then
				normalized_config[key] = value
			else
				normalized_config[key] = { enabled = false }
			end
		else
			normalized_config[key] = value
		end
	end
	
	manager_config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, normalized_config)
	
	debug_log("Initializing completion manager")
	
	-- Initialize utils system
	if not utils then
		local ok
		ok, utils = pcall(require, "pebble.completion.utils")
		if not ok then
			vim.notify("Failed to load completion utils", vim.log.levels.ERROR)
			return false
		end
	end
	utils.setup({
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
	
	-- Check if already registered and prevent_conflicts is enabled
	if manager_config.prevent_conflicts and registered_sources.nvim_cmp then
		return true, "already registered"
	end
	
	local ok, nvim_cmp_module = pcall(require, "pebble.completion.nvim_cmp")
	if not ok then
		return false, "nvim-cmp completion module not found"
	end
	
	if not nvim_cmp_module.is_available() then
		return false, "nvim-cmp not installed or available"
	end
	
	local success, result = nvim_cmp_module.register(opts)
	if success then
		registered_sources.nvim_cmp = {
			status = "registered",
			timestamp = os.time(),
			opts = opts
		}
		
		-- Setup filetype-specific configuration if enabled
		if opts.filetype_setup ~= false then
			M.setup_nvim_cmp_filetype(opts)
		end
		
		return true, result or "registered"
	else
		return false, result or "registration failed"
	end
end

-- Register blink.cmp source
function M.register_blink_cmp(opts)
	opts = opts or {}
	
	-- Check if already registered and prevent_conflicts is enabled
	if manager_config.prevent_conflicts and registered_sources.blink_cmp then
		return true, "already registered"
	end
	
	local ok, blink_cmp_module = pcall(require, "pebble.completion.blink_cmp")
	if not ok then
		return false, "blink.cmp completion module not found"
	end
	
	if not blink_cmp_module.is_available() then
		return false, "blink.cmp not installed or available"
	end
	
	local success, result = blink_cmp_module.register(opts)
	if success then
		registered_sources.blink_cmp = {
			status = "registered",
			timestamp = os.time(),
			opts = opts
		}
		return true, result or "registered"
	else
		return false, result or "registration failed"
	end
end

-- Setup filetype-specific nvim-cmp configuration
function M.setup_nvim_cmp_filetype(opts)
	opts = opts or {}
	
	if not opts.auto_add_to_sources then
		return
	end
	
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "markdown", "md", "mdx" },
		callback = function()
			local cmp_ok, cmp = pcall(require, 'cmp')
			if not cmp_ok then
				return
			end
			
			-- Get current buffer config
			local success, buf_config = pcall(cmp.get_config)
			if not success then
				return
			end
			
			local current_sources = buf_config and buf_config.sources or {}
			
			-- Check if our source is already added
			local already_added = false
			for _, source_group in ipairs(current_sources) do
				if type(source_group) == "table" then
					for _, source in ipairs(source_group) do
						if type(source) == "table" and source.name == 'pebble' then
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
				
				-- Add pebble as a high-priority source
				table.insert(new_sources, 1, { 
					{ name = 'pebble', priority = opts.priority or 100 }
				})
				
				local setup_ok, setup_err = pcall(cmp.setup.buffer, {
					sources = new_sources
				})
				
				if not setup_ok and opts.debug then
					debug_log("Failed to setup buffer sources: " .. tostring(setup_err))
				end
			end
		end,
		group = vim.api.nvim_create_augroup("PebbleNvimCmpFiletype", { clear = true })
	})
end

-- Setup automatic cache invalidation
function M.setup_cache_invalidation()
	-- Invalidate cache when files change
	vim.api.nvim_create_autocmd({ "BufWritePost", "BufNewFile", "BufDelete" }, {
		pattern = "*.md",
		callback = function()
			if utils then utils.invalidate_cache() end
			debug_log("Cache invalidated due to file change")
		end,
		group = vim.api.nvim_create_augroup("PebbleCompletionCacheInvalidation", { clear = true })
	})
end

-- Get manager status and statistics
function M.get_status()
	local utils_stats = utils and utils.get_stats() or {}
	
	-- Get detailed status for each registered source
	local source_details = {}
	for source_name, source_info in pairs(registered_sources) do
		if source_name == "nvim_cmp" then
			local ok, nvim_cmp_module = pcall(require, "pebble.completion.nvim_cmp")
			if ok then
				source_details.nvim_cmp = nvim_cmp_module.get_status()
			end
		elseif source_name == "blink_cmp" then
			local ok, blink_cmp_module = pcall(require, "pebble.completion.blink_cmp")
			if ok and blink_cmp_module.get_status then
				source_details.blink_cmp = blink_cmp_module.get_status()
			end
		end
	end
	
	return {
		initialized = is_initialized,
		config = manager_config,
		registered_sources = registered_sources,
		source_details = source_details,
		completion_stats = utils_stats,
		available_engines = {
			nvim_cmp = pcall(require, "cmp") and true or false,
			blink_cmp = pcall(require, "blink.cmp") and true or false,
		}
	}
end

-- Manual cache refresh
function M.refresh_cache()
	if utils then utils.invalidate_cache() end
	debug_log("Manual cache refresh triggered")
	return true
end

-- Test completion functionality
function M.test_completion()
	if not utils then return {} end
	local is_wiki, wiki_query = utils.is_wiki_link_context()
	local is_markdown, markdown_query = utils.is_markdown_link_context()
	
	local results = {}
	
	if is_wiki then
		local root_dir = utils.get_root_dir()
		local completions = utils.get_wiki_completions(wiki_query, root_dir)
		results.wiki_links = {
			query = wiki_query,
			count = #completions,
			items = vim.tbl_map(function(item) return item.label end, vim.list_slice(completions, 1, 5))
		}
	elseif is_markdown then
		local root_dir = utils.get_root_dir()
		local completions = utils.get_markdown_link_completions(markdown_query, root_dir)
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
	
	-- Validate setup and configuration
	vim.api.nvim_create_user_command("PebbleValidateSetup", function()
		M.validate_setup()
	end, { desc = "Validate Pebble completion setup" })
	
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
			"  Valid: " .. tostring((status.completion_stats.cache or {}).valid),
			"  Size: " .. ((status.completion_stats.cache or {}).size or 0) .. " items",
			"  Hits: " .. ((status.completion_stats.cache or {}).hits or 0),
			"  Misses: " .. ((status.completion_stats.cache or {}).misses or 0),
		}
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
	end, { desc = "Show Pebble completion status" })
	
	-- Refresh cache
	vim.api.nvim_create_user_command("PebbleRefreshCache", function()
		M.refresh_cache()
		vim.notify("Pebble completion cache refreshed", vim.log.levels.INFO)
	end, { desc = "Refresh Pebble completion cache" })
end

-- Validate the completion setup
function M.validate_setup()
	local status = M.get_status()
	local issues = {}
	local warnings = {}
	
	-- Check initialization
	if not status.initialized then
		table.insert(issues, "Manager not initialized - call setup() first")
	end
	
	-- Check if any completion engines are available
	if not status.available_engines.nvim_cmp and not status.available_engines.blink_cmp then
		table.insert(issues, "No completion engines available - install nvim-cmp or blink.cmp")
	end
	
	-- Check for source registration conflicts
	local registered_count = 0
	for _, _ in pairs(status.registered_sources) do
		registered_count = registered_count + 1
	end
	
	if registered_count == 0 then
		table.insert(warnings, "No completion sources registered")
	elseif registered_count > 1 then
		table.insert(warnings, "Multiple completion sources registered - may cause conflicts")
	end
	
	-- Check completion functionality
	if vim.bo.filetype == "markdown" then
		local test_results = M.test_completion()
		if test_results.error then
			table.insert(warnings, "Completion test failed: " .. test_results.error)
		end
	else
		table.insert(warnings, "Not in markdown file - some tests skipped")
	end
	
	-- Report results
	local report_lines = { "=== Pebble Completion Validation ===" }
	
	if #issues > 0 then
		table.insert(report_lines, "\n❌ Issues:")
		for _, issue in ipairs(issues) do
			table.insert(report_lines, "  • " .. issue)
		end
	end
	
	if #warnings > 0 then
		table.insert(report_lines, "\n⚠️  Warnings:")
		for _, warning in ipairs(warnings) do
			table.insert(report_lines, "  • " .. warning)
		end
	end
	
	if #issues == 0 and #warnings == 0 then
		table.insert(report_lines, "\n✅ Setup looks good!")
	end
	
	table.insert(report_lines, "\n--- Configuration ---")
	table.insert(report_lines, "Engines available: " .. vim.inspect(status.available_engines))
	table.insert(report_lines, "Sources registered: " .. vim.inspect(vim.tbl_keys(status.registered_sources)))
	
	vim.notify(table.concat(report_lines, "\n"), #issues > 0 and vim.log.levels.ERROR or vim.log.levels.INFO)
	
	return #issues == 0
end

return M
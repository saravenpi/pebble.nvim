local M = {}

-- Git root caching now handled by centralized search utility

-- Simple module loading
local parser = require("pebble.bases.parser")
local filters = require("pebble.bases.filters")  
local formulas = require("pebble.bases.formulas")
local views = require("pebble.bases.views")
local cache = require("pebble.bases.cache")

local function get_root_dir()
	local search = require("pebble.bases.search")
	return search.get_root_dir()
end

-- Enhanced async version of open_base
function M.open_base_async(base_path, callback)
	callback = callback or function() end
	
	-- Basic validation
	if not base_path or base_path == "" then
		vim.notify("No base file path provided", vim.log.levels.ERROR)
		callback(false, "No base file path provided")
		return
	end
	
	if vim.fn.filereadable(base_path) ~= 1 then
		vim.notify("Base file not found: " .. base_path, vim.log.levels.ERROR)
		callback(false, "Base file not found")
		return
	end
	
	-- Load base data
	local base_data, err = cache.get_base_data(base_path)
	if not base_data then
		vim.notify("Failed to load base: " .. (err or "Unknown error"), vim.log.levels.ERROR)
		callback(false, "Failed to load base: " .. (err or "Unknown error"))
		return
	end
	
	-- Get file data asynchronously
	local root_dir = get_root_dir()
	cache.get_file_data_async(root_dir, false, function(files, file_err)
		if file_err then
			vim.notify("Error loading file data: " .. file_err, vim.log.levels.ERROR)
			views.open_base_view(base_data, {})
			callback(false, file_err)
			return
		end
		
		files = files or {}
		if #files == 0 then
			vim.notify("No markdown files found in " .. root_dir .. ". Check if you have .md files in your directory.", vim.log.levels.INFO)
			views.open_base_view(base_data, {})
			callback(true)
			return
		end
		
		-- Process filters and views asynchronously
		M.process_base_async(base_data, files, function(processed_files)
			views.open_base_view(base_data, processed_files)
			callback(true)
		end)
	end)
end

-- Synchronous version for backwards compatibility
function M.open_base(base_path)
	-- Basic validation
	if not base_path or base_path == "" then
		vim.notify("No base file path provided", vim.log.levels.ERROR)
		return
	end
	
	if vim.fn.filereadable(base_path) ~= 1 then
		vim.notify("Base file not found: " .. base_path, vim.log.levels.ERROR)
		return
	end
	
	-- Load base data
	local base_data, err = cache.get_base_data(base_path)
	if not base_data then
		vim.notify("Failed to load base: " .. (err or "Unknown error"), vim.log.levels.ERROR)
		return
	end
	
	-- Try async first, fallback to sync if needed
	local root_dir = get_root_dir()
	if vim.in_fast_event() then
		-- We're in a fast event, schedule async processing
		vim.schedule(function()
			M.open_base_async(base_path)
		end)
		return
	end
	
	-- Synchronous fallback
	local ok, files = pcall(cache.get_file_data, root_dir)
	
	if not ok then
		vim.notify("Error loading file data: " .. tostring(files), vim.log.levels.ERROR)
		views.open_base_view(base_data, {})
		return
	end
	
	files = files or {}
	if #files == 0 then
		vim.notify("No markdown files found in " .. root_dir .. ". Check if you have .md files in your directory.", vim.log.levels.INFO)
		views.open_base_view(base_data, {})
		return
	end
	
	-- Process base synchronously
	local processed_files = M.process_base_sync(base_data, files)
	views.open_base_view(base_data, processed_files)
end

-- Async processing of base filters, views, and formulas
function M.process_base_async(base_data, files, callback)
	callback = callback or function() end
	
	local function process_step(step_files)
		-- Apply base filters with timeout protection
		if base_data.filters then
			vim.schedule(function()
				local start_time = vim.loop.now()
				local ok, result = pcall(filters.filter_files, step_files, base_data.filters)
				local duration = vim.loop.now() - start_time
				
				if ok and result then
					step_files = result
					if duration > 1000 then
						vim.notify("Base filtering took " .. duration .. "ms - consider optimizing filters", vim.log.levels.WARN)
					end
				else
					vim.notify("Error applying base filters: " .. tostring(result), vim.log.levels.WARN)
				end
				
				process_views(step_files)
			end)
		else
			process_views(step_files)
		end
	end
	
	local function process_views(step_files)
		-- Apply view-specific filtering and ordering
		if base_data.views and #base_data.views > 0 then
			local view = base_data.views[1]
			
			if view.filters then
				vim.schedule(function()
					local start_time = vim.loop.now()
					local ok, result = pcall(filters.filter_files, step_files, view.filters)
					local duration = vim.loop.now() - start_time
					
					if ok and result then
						step_files = result
						if duration > 1000 then
							vim.notify("View filtering took " .. duration .. "ms - consider optimizing filters", vim.log.levels.WARN)
						end
					else
						vim.notify("Error applying view filters: " .. tostring(result), vim.log.levels.WARN)
					end
					
					process_sort(step_files, view)
				end)
			else
				process_sort(step_files, view)
			end
		else
			process_formulas(step_files)
		end
	end
	
	local function process_sort(step_files, view)
		if view.order and type(view.order) == "table" and #view.order > 0 then
			vim.schedule(function()
				pcall(table.sort, step_files, function(a, b)
					if type(a) ~= "table" or type(b) ~= "table" then
						return false
					end
					
					for _, order_key in ipairs(view.order) do
						local ascending = true
						if order_key:match("^%-") then
							ascending = false
							order_key = order_key:sub(2)
						end
						
						local a_val = a[order_key]
						local b_val = b[order_key]
						
						if a_val ~= b_val then
							if ascending then
								return tostring(a_val or "") < tostring(b_val or "")
							else
								return tostring(a_val or "") > tostring(b_val or "")
							end
						end
					end
					return false
				end)
				
				process_formulas(step_files)
			end)
		else
			process_formulas(step_files)
		end
	end
	
	local function process_formulas(step_files)
		-- Apply formulas with error handling
		if base_data.formulas and vim.tbl_count(base_data.formulas) > 0 then
			vim.schedule(function()
				local start_time = vim.loop.now()
				local ok, result = pcall(formulas.apply_formulas_to_files, step_files, base_data.formulas)
				local duration = vim.loop.now() - start_time
				
				if ok and result then
					step_files = result
					if duration > 1000 then
						vim.notify("Formula processing took " .. duration .. "ms", vim.log.levels.WARN)
					end
				else
					vim.notify("Error applying formulas: " .. tostring(result), vim.log.levels.WARN)
				end
				
				callback(step_files)
			end)
		else
			callback(step_files)
		end
	end
	
	-- Start the processing chain
	process_step(files)
end

-- Synchronous processing for backwards compatibility
function M.process_base_sync(base_data, files)
	-- Apply base filters with timeout protection
	if base_data.filters then
		local start_time = vim.loop.now()
		local ok, result = pcall(filters.filter_files, files, base_data.filters)
		local duration = vim.loop.now() - start_time
		
		if ok and result then
			files = result
			if duration > 1000 then -- Log if filtering took more than 1 second
				vim.notify("Base filtering took " .. duration .. "ms - consider optimizing filters", vim.log.levels.WARN)
			end
		else
			vim.notify("Error applying base filters: " .. tostring(result), vim.log.levels.WARN)
		end
	end
	
	-- Apply view-specific filtering and ordering
	if base_data.views and #base_data.views > 0 then
		local view = base_data.views[1]
		
		-- Apply view filters with timeout protection
		if view.filters then
			local start_time = vim.loop.now()
			local ok, result = pcall(filters.filter_files, files, view.filters)
			local duration = vim.loop.now() - start_time
			
			if ok and result then
				files = result
				if duration > 1000 then
					vim.notify("View filtering took " .. duration .. "ms - consider optimizing filters", vim.log.levels.WARN)
				end
			else
				vim.notify("Error applying view filters: " .. tostring(result), vim.log.levels.WARN)
			end
		end
		
		-- Apply sorting
		if view.order and type(view.order) == "table" and #view.order > 0 then
			pcall(table.sort, files, function(a, b)
				if type(a) ~= "table" or type(b) ~= "table" then
					return false
				end
				
				for _, order_key in ipairs(view.order) do
					local ascending = true
					if order_key:match("^%-") then
						ascending = false
						order_key = order_key:sub(2)
					end
					
					local a_val = a[order_key]
					local b_val = b[order_key]
					
					if a_val ~= b_val then
						if ascending then
							return tostring(a_val or "") < tostring(b_val or "")
						else
							return tostring(a_val or "") > tostring(b_val or "")
						end
					end
				end
				return false
			end)
		end
	end
	
	-- Apply formulas with error handling
	if base_data.formulas and vim.tbl_count(base_data.formulas) > 0 then
		local start_time = vim.loop.now()
		local ok, result = pcall(formulas.apply_formulas_to_files, files, base_data.formulas)
		local duration = vim.loop.now() - start_time
		
		if ok and result then
			files = result
			if duration > 1000 then
				vim.notify("Formula processing took " .. duration .. "ms", vim.log.levels.WARN)
			end
		else
			vim.notify("Error applying formulas: " .. tostring(result), vim.log.levels.WARN)
		end
	end
	
	return files
end

function M.open_current_base()
	local current_file = vim.fn.expand("%:p")
	
	if current_file:match("%.base$") then
		-- Currently in a base file, use async version if possible
		if vim.in_fast_event() then
			vim.schedule(function()
				M.open_base_async(current_file)
			end)
		else
			M.open_base_async(current_file)
		end
	else
		-- Find and open first available base
		local root_dir = get_root_dir()
		
		-- Use async base finding if available
		if parser.find_base_files_async then
			parser.find_base_files_async(root_dir, function(bases, err)
				if err then
					vim.notify("Error finding base files: " .. err, vim.log.levels.ERROR)
					return
				end
				
				if #bases == 0 then
					vim.notify("No .base files found in " .. root_dir, vim.log.levels.WARN)
					return
				elseif #bases == 1 then
					vim.notify("Opening " .. bases[1].relative_path, vim.log.levels.INFO)
					M.open_base_async(bases[1].path)
				else
					vim.notify("Opening first of " .. #bases .. " available bases: " .. bases[1].relative_path .. " (use :PebbleBases to select)", vim.log.levels.INFO)
					M.open_base_async(bases[1].path)
				end
			end)
		else
			-- Fallback to synchronous
			local bases = parser.find_base_files(root_dir)
			
			if #bases == 0 then
				vim.notify("No .base files found in " .. root_dir, vim.log.levels.WARN)
				return
			elseif #bases == 1 then
				vim.notify("Opening " .. bases[1].relative_path, vim.log.levels.INFO)
				M.open_base(bases[1].path)
			else
				vim.notify("Opening first of " .. #bases .. " available bases: " .. bases[1].relative_path .. " (use :PebbleBases to select)", vim.log.levels.INFO)
				M.open_base(bases[1].path)
			end
		end
	end
end

-- Enhanced list_bases with better error handling and async support
function M.list_bases()
	-- Check if telescope is available using the same function as views
	local telescope_ok, telescope_modules = views and pcall(views.check_telescope) or {false}
	if not telescope_ok or not telescope_modules then
		vim.notify("Telescope is required for bases functionality. Please install telescope.nvim", vim.log.levels.ERROR)
		return
	end
	
	local root_dir = get_root_dir()
	
	-- Try async version first
	if parser.find_base_files_async then
		parser.find_base_files_async(root_dir, function(bases, err)
			if err then
				vim.notify("Error finding base files: " .. err, vim.log.levels.ERROR)
				-- Fallback to sync
				M.list_bases_sync(root_dir)
				return
			end
			
			if #bases == 0 then
				vim.notify("No .base files found in " .. root_dir, vim.log.levels.INFO)
				return
			end
			
			M.create_base_picker(bases)
		end)
	else
		M.list_bases_sync(root_dir)
	end
end

-- Synchronous fallback for list_bases
function M.list_bases_sync(root_dir)
	local ok, bases = pcall(parser.find_base_files, root_dir)
	
	if not ok then
		vim.notify("Error finding base files: " .. tostring(bases), vim.log.levels.ERROR)
		return
	end
	
	if #bases == 0 then
		vim.notify("No .base files found in " .. root_dir, vim.log.levels.INFO)
		return
	end
	
	M.create_base_picker(bases)
end

-- Create telescope picker for base selection
function M.create_base_picker(bases)
	local telescope_ok, telescope = pcall(require, 'telescope')
	if not telescope_ok then
		vim.notify("Telescope not available", vim.log.levels.ERROR)
		return
	end
	
	local pickers_ok, pickers = pcall(require, 'telescope.pickers')
	local finders_ok, finders = pcall(require, 'telescope.finders')  
	local conf_ok, conf = pcall(require, 'telescope.config')
	local actions_ok, actions = pcall(require, 'telescope.actions')
	local action_state_ok, action_state = pcall(require, 'telescope.actions.state')
	
	if not (pickers_ok and finders_ok and conf_ok and actions_ok and action_state_ok) then
		vim.notify("Telescope modules not available. Please ensure telescope.nvim is properly installed", vim.log.levels.ERROR)
		return
	end
	
	-- Safely create telescope picker
	local ok, picker = pcall(pickers.new, {}, {
		prompt_title = "Select Base File",
		finder = finders.new_table({
			results = bases,
			entry_maker = function(base)
				if not base or not base.relative_path then
					return {
						value = base,
						display = "[Invalid base entry]",
						ordinal = "invalid",
					}
				end
				
				return {
					value = base,
					display = base.relative_path,
					ordinal = base.relative_path,
					path = base.path,
				}
			end,
		}),
		sorter = conf.values.generic_sorter and conf.values.generic_sorter({}) or conf.values.file_sorter({}),
		attach_mappings = function(prompt_bufnr, map)
			local function safe_select()
				local selection = action_state.get_selected_entry()
				if selection and selection.value and selection.value.path then
					local path = selection.value.path
					if vim.fn.filereadable(path) == 1 then
						M.open_base_async(path, function(success, err)
							if not success then
								vim.notify("Failed to open base: " .. (err or "unknown error"), vim.log.levels.ERROR)
							end
						end)
					else
						vim.notify("Base file not found: " .. path, vim.log.levels.ERROR)
					end
				else
					vim.notify("No valid base selected", vim.log.levels.WARN)
				end
			end
			
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				safe_select()
			end)
			
			-- Add preview keybinding
			map('i', '<C-p>', function()
				local selection = action_state.get_selected_entry()
				if selection and selection.value and selection.value.path then
					vim.notify("Base path: " .. selection.value.path, vim.log.levels.INFO)
				end
			end)
			
			return true
		end,
	})
	
	if not ok then
		vim.notify("Error creating telescope picker: " .. tostring(picker), vim.log.levels.ERROR)
		return
	end
	
	-- Safely start the picker
	local start_ok, start_err = pcall(function() picker:find() end)
	if not start_ok then
		vim.notify("Error starting telescope picker: " .. tostring(start_err), vim.log.levels.ERROR)
	end
end

-- Enhanced error recovery and diagnostics
function M.diagnose()
	local diagnostics = {
		telescope_available = pcall(require, 'telescope'),
		ripgrep_available = search and search.has_ripgrep() or false,
		cache_stats = cache.get_cache_stats and cache.get_cache_stats() or {},
		git_root = get_root_dir(),
	}
	
	local root_dir = diagnostics.git_root
	local base_count = 0
	local md_count = 0
	
	-- Count base files
	local ok, bases = pcall(parser.find_base_files, root_dir)
	if ok and bases then
		base_count = #bases
	end
	
	-- Count markdown files
	local ok2, files = pcall(cache.get_file_data, root_dir)
	if ok2 and files then
		md_count = #files
	end
	
	diagnostics.base_files_count = base_count
	diagnostics.markdown_files_count = md_count
	
	-- Display diagnostics
	local lines = {
		"Pebble Bases Diagnostics:",
		"========================",
		"Telescope available: " .. tostring(diagnostics.telescope_available),
		"Ripgrep available: " .. tostring(diagnostics.ripgrep_available),
		"Git root: " .. diagnostics.git_root,
		"Base files found: " .. diagnostics.base_files_count,
		"Markdown files found: " .. diagnostics.markdown_files_count,
		"Cache entries: " .. vim.inspect(diagnostics.cache_stats),
	}
	
	print(table.concat(lines, "\n"))
	return diagnostics
end

-- Clear all caches and reset state
function M.reset()
	vim.notify("Resetting pebble bases...", vim.log.levels.INFO)
	
	-- Clear all caches
	cache.clear_cache()
	
	-- Clear search cache
	if search and search.clear_cache then
		search.clear_cache()
	end
	
	-- Clear filter content cache
	local filters = require("pebble.bases.filters")
	if filters.clear_content_cache then
		filters.clear_content_cache()
	end
	
	-- Reset git root cache
	_git_root_cache = nil
	_git_root_cache_time = 0
	
	vim.notify("Pebble bases reset complete", vim.log.levels.INFO)
end

return M
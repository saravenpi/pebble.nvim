local M = {}

-- Load debug module first
local debug = require("pebble.bases.debug")

-- Safe module loading with error boundaries
local parser, filters, formulas, views, cache

local function safe_require(module_name, component_name)
    debug.info("INIT", "Loading module: " .. module_name)
    local ok, module = pcall(require, module_name)
    if ok then
        debug.set_component_state(component_name, "loaded")
        debug.info("INIT", "Successfully loaded " .. module_name)
        return module
    else
        debug.error("INIT", "Failed to load " .. module_name, module)
        debug.set_component_state(component_name, "failed")
        return nil
    end
end

-- Initialize modules with error handling
parser = safe_require("pebble.bases.parser", "parser")
filters = safe_require("pebble.bases.filters", "filters") 
formulas = safe_require("pebble.bases.formulas", "formulas")
views = safe_require("pebble.bases.views", "views")
cache = safe_require("pebble.bases.cache", "cache")

-- Validate critical dependencies
local function validate_dependencies()
    local missing = {}
    if not parser then table.insert(missing, "parser") end
    if not filters then table.insert(missing, "filters") end
    if not formulas then table.insert(missing, "formulas") end 
    if not views then table.insert(missing, "views") end
    if not cache then table.insert(missing, "cache") end
    
    if #missing > 0 then
        debug.error("INIT", "Missing critical dependencies", missing)
        return false, missing
    end
    
    debug.info("INIT", "All dependencies loaded successfully")
    return true
end

-- Initialize the system
local dependencies_ok, missing_deps = validate_dependencies()
if not dependencies_ok then
    vim.notify("Pebble bases failed to initialize: missing " .. table.concat(missing_deps, ", "), vim.log.levels.ERROR)
end

local function get_root_dir()
	local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
	if vim.v.shell_error ~= 0 or git_root == "" then
		return vim.fn.getcwd()
	end
	return git_root
end

function M.open_base(base_path)
	debug.enter_function("INIT", "open_base", {base_path = base_path})
	
	-- Check system health first
	if not dependencies_ok then
		debug.error("INIT", "Cannot open base - system not initialized", missing_deps)
		vim.notify("Pebble bases system not initialized properly", vim.log.levels.ERROR)
		debug.exit_function("INIT", "open_base", "system_not_ready")
		return
	end
	
	-- Comprehensive input validation
	local validation_ok, validation_error = debug.validate_input("INIT", "open_base", {
		base_path = {
			value = base_path,
			type = "string", 
			required = true,
			check = function(path) return path ~= "" end
		}
	})
	
	if not validation_ok then
		vim.notify("Invalid base path: " .. validation_error, vim.log.levels.ERROR)
		debug.exit_function("INIT", "open_base", "invalid_input")
		return
	end
	
	-- Check file exists
	local file_readable = debug.safe_call("INIT", "filereadable_check", vim.fn.filereadable, base_path)
	if not file_readable or file_readable == 0 then
		debug.error("INIT", "Base file not found or not readable", base_path)
		vim.notify("Base file not found: " .. base_path, vim.log.levels.ERROR)
		debug.exit_function("INIT", "open_base", "file_not_found")
		return
	end
	
	-- Load base data with error boundary
	debug.info("INIT", "Loading base data from", base_path)
	local load_ok, base_data, err = debug.safe_call("INIT", "get_base_data", cache.get_base_data, base_path)
	
	if not load_ok or not base_data then
		debug.error("INIT", "Failed to load base data", {error = err, path = base_path})
		vim.notify("Failed to load base: " .. (err or "Unknown error"), vim.log.levels.ERROR)
		debug.exit_function("INIT", "open_base", "base_load_failed")
		return
	end
	
	debug.info("INIT", "Base data loaded successfully", {
		filters_count = base_data.filters and 1 or 0,
		views_count = base_data.views and #base_data.views or 0,
		formulas_count = base_data.formulas and vim.tbl_count(base_data.formulas) or 0
	})
	
	-- Get file data with error boundary
	local get_root_ok, root_dir = debug.safe_call("INIT", "get_root_dir", get_root_dir)
	if not get_root_ok or not root_dir then
		debug.error("INIT", "Failed to get root directory", root_dir)
		vim.notify("Failed to determine root directory", vim.log.levels.ERROR)
		debug.exit_function("INIT", "open_base", "root_dir_failed")
		return
	end
	
	debug.info("INIT", "Getting file data from root", root_dir)
	local files_ok, files = debug.safe_call("INIT", "get_file_data", cache.get_file_data, root_dir)
	
	if not files_ok then
		debug.error("INIT", "Failed to get file data", files)
		vim.notify("Failed to load files from " .. root_dir, vim.log.levels.ERROR) 
		debug.exit_function("INIT", "open_base", "files_load_failed")
		return
	end
	
	if not files or #files == 0 then
		debug.warn("INIT", "No markdown files found", {root_dir = root_dir})
		vim.notify("No markdown files found in " .. root_dir, vim.log.levels.WARN)
		-- Still try to show the view with empty data
		local view_ok, view_result = debug.safe_call("INIT", "open_base_view_empty", views.open_base_view, base_data, {})
		debug.exit_function("INIT", "open_base", "no_files_found")
		return
	end
	
	debug.info("INIT", "Found files for processing", {count = #files})
	
	
	-- Apply filters safely with comprehensive error handling
	if base_data.filters then
		debug.info("INIT", "Applying base filters", base_data.filters)
		local filter_ok, filtered_files = debug.safe_call("INIT", "apply_base_filters", filters.filter_files, files, base_data.filters)
		
		if filter_ok and filtered_files then
			files = filtered_files
			debug.info("INIT", "Base filters applied successfully", {original_count = #files, filtered_count = #filtered_files})
		else
			debug.error("INIT", "Error applying base filters", filtered_files)
			vim.notify("Error applying filters: " .. (filtered_files or "Unknown error"), vim.log.levels.ERROR)
			-- Continue with unfiltered files rather than crashing
		end
	end
	
	-- Apply view-specific filtering and ordering with error boundaries
	if base_data.views and #base_data.views > 0 then
		local view = base_data.views[1]
		debug.info("INIT", "Processing view configuration", {type = view.type, has_filters = view.filters ~= nil, has_order = view.order ~= nil})
		
		if view.filters then
			debug.info("INIT", "Applying view filters", view.filters)
			local view_filter_ok, view_filtered_files = debug.safe_call("INIT", "apply_view_filters", filters.filter_files, files, view.filters)
			
			if view_filter_ok and view_filtered_files then
				files = view_filtered_files
				debug.info("INIT", "View filters applied successfully", {count = #files})
			else
				debug.error("INIT", "Error applying view filters", view_filtered_files)
				vim.notify("Error applying view filters: " .. (view_filtered_files or "Unknown error"), vim.log.levels.ERROR)
				-- Continue with existing files
			end
		end
		
		if view.order and type(view.order) == "table" and #view.order > 0 then
			debug.info("INIT", "Applying sort order", view.order)
			local sort_ok = debug.safe_call("INIT", "sort_files", function()
				table.sort(files, function(a, b)
					-- Ensure both files are tables before processing
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
				return true
			end)
			
			if sort_ok then
				debug.info("INIT", "Files sorted successfully")
			else
				debug.warn("INIT", "Error sorting files - continuing with unsorted data")
				vim.notify("Warning: Could not sort files", vim.log.levels.WARN)
			end
		end
	end
	
	-- Apply formulas safely with error boundary
	if base_data.formulas and vim.tbl_count(base_data.formulas) > 0 then
		debug.info("INIT", "Applying formulas", {count = vim.tbl_count(base_data.formulas)})
		local formulas_ok, formula_result = debug.safe_call("INIT", "apply_formulas", formulas.apply_formulas_to_files, files, base_data.formulas)
		
		if formulas_ok and formula_result then
			files = formula_result
			debug.info("INIT", "Formulas applied successfully")
		else
			debug.error("INIT", "Error applying formulas", formula_result)
			vim.notify("Error applying formulas: " .. (formula_result or "Unknown error"), vim.log.levels.ERROR)
			-- Continue with files without formulas
		end
	end
	
	-- Open the view with final error boundary
	debug.info("INIT", "Opening base view", {files_count = #files})
	local view_ok, view_result = debug.safe_call("INIT", "open_base_view_final", views.open_base_view, base_data, files)
	
	if view_ok then
		debug.info("INIT", "Base view opened successfully")
		debug.exit_function("INIT", "open_base", "success")
	else
		debug.error("INIT", "Failed to open base view", view_result)
		vim.notify("Failed to open base view: " .. (view_result or "Unknown error"), vim.log.levels.ERROR)
		debug.exit_function("INIT", "open_base", "view_failed")
	end
end

function M.open_current_base()
	debug.enter_function("INIT", "open_current_base", {})
	
	-- Check system health first
	if not dependencies_ok then
		debug.error("INIT", "Cannot open current base - system not initialized", missing_deps)
		vim.notify("Pebble bases system not initialized properly", vim.log.levels.ERROR)
		debug.exit_function("INIT", "open_current_base", "system_not_ready")
		return
	end
	
	local process_ok, result = debug.safe_call("INIT", "open_current_base_logic", function()
		-- Get current file safely
		local current_file_ok, current_file = debug.safe_call("INIT", "expand_current_path", vim.fn.expand, "%:p")
		if not current_file_ok or not current_file or current_file == "" then
			debug.warn("INIT", "Could not get current file path")
			current_file = ""
		end
		
		debug.info("INIT", "Current file detected", {path = current_file})
		
		if current_file:match("%.base$") then
			-- If currently in a .base file, open it
			debug.info("INIT", "Opening current base file directly")
			return M.open_base(current_file)
		else
			-- If not in a .base file, find and open the first available base
			local root_dir_ok, root_dir = debug.safe_call("INIT", "get_root_dir_for_current", get_root_dir)
			if not root_dir_ok or not root_dir then
				debug.error("INIT", "Failed to get root directory for current base", root_dir)
				vim.notify("Failed to determine root directory", vim.log.levels.ERROR)
				return false
			end
			
			debug.info("INIT", "Searching for base files in", root_dir)
			local bases_ok, bases = debug.safe_call("INIT", "find_base_files", parser.find_base_files, root_dir)
			if not bases_ok or not bases then
				debug.error("INIT", "Failed to find base files", bases)
				vim.notify("Failed to search for base files", vim.log.levels.ERROR)
				return false
			end
			
			debug.info("INIT", "Found base files", {count = #bases})
			
			if #bases == 0 then
				debug.warn("INIT", "No base files found in directory", {root_dir = root_dir})
				vim.notify("No .base files found in " .. root_dir, vim.log.levels.WARN)
				return false
			elseif #bases == 1 then
				-- Only one base file, open it directly
				debug.info("INIT", "Opening single base file", bases[1])
				vim.notify("Opening " .. bases[1].relative_path, vim.log.levels.INFO)
				return M.open_base(bases[1].path)
			else
				-- Multiple bases available, open the first one by default
				debug.info("INIT", "Opening first of multiple bases", {count = #bases, first = bases[1]})
				vim.notify("Opening first of " .. #bases .. " available bases: " .. bases[1].relative_path .. " (use :PebbleBases to select)", vim.log.levels.INFO)
				return M.open_base(bases[1].path)
			end
		end
	end)
	
	if process_ok then
		debug.info("INIT", "open_current_base completed successfully")
		debug.exit_function("INIT", "open_current_base", "success")
	else
		debug.error("INIT", "Error in open_current_base", result)
		vim.notify("Error in open_current_base: " .. tostring(result), vim.log.levels.ERROR)
		debug.exit_function("INIT", "open_current_base", "failed")
	end
end

function M.list_bases()
	debug.enter_function("INIT", "list_bases", {})
	
	-- Check system health first
	if not dependencies_ok then
		debug.error("INIT", "Cannot list bases - system not initialized", missing_deps)
		vim.notify("Pebble bases system not initialized properly", vim.log.levels.ERROR)
		debug.exit_function("INIT", "list_bases", "system_not_ready")
		return
	end
	
	local list_ok, result = debug.safe_call("INIT", "list_bases_logic", function()
		-- Get root directory safely
		local root_dir_ok, root_dir = debug.safe_call("INIT", "get_root_dir_for_list", get_root_dir)
		if not root_dir_ok or not root_dir then
			debug.error("INIT", "Failed to get root directory for list", root_dir)
			vim.notify("Failed to determine root directory", vim.log.levels.ERROR)
			return false
		end
		
		debug.info("INIT", "Searching for bases to list in", root_dir)
		local bases_ok, bases = debug.safe_call("INIT", "find_base_files_for_list", parser.find_base_files, root_dir)
		if not bases_ok or not bases then
			debug.error("INIT", "Failed to find base files for listing", bases)
			vim.notify("Failed to search for base files", vim.log.levels.ERROR)
			return false
		end
		
		debug.info("INIT", "Found bases for listing", {count = #bases})
		
		if #bases == 0 then
			debug.warn("INIT", "No base files found for listing", {root_dir = root_dir})
			vim.notify("No .base files found in " .. root_dir, vim.log.levels.INFO)
			return true -- Not an error, just no bases found
		end
		
		-- Create selection with timeout protection
		local selection_made = false
		local selection_timeout = false
		
		local function safe_callback(choice, idx)
			if selection_made or selection_timeout then 
				debug.warn("INIT", "Selection callback called after timeout or duplicate")
				return 
			end
			selection_made = true
			
			debug.info("INIT", "User selected base", {choice = choice, idx = idx})
			
			if choice and idx and bases[idx] then
				local open_ok, open_err = debug.safe_call("INIT", "open_selected_base", M.open_base, bases[idx].path)
				if not open_ok then
					debug.error("INIT", "Error opening selected base", {path = bases[idx].path, error = open_err})
					vim.notify("Error opening base: " .. tostring(open_err), vim.log.levels.ERROR)
				end
			else
				debug.warn("INIT", "Invalid selection received", {choice = choice, idx = idx})
			end
		end
		
		-- Set timeout for selection
		vim.defer_fn(function()
			if not selection_made then
				selection_timeout = true
				debug.warn("INIT", "Base selection timed out")
			end
		end, 30000) -- 30 second timeout
		
		-- Create item list safely
		local items_ok, items = debug.safe_call("INIT", "map_base_paths", function()
			return vim.tbl_map(function(base) 
				return base.relative_path or base.path or "unknown" 
			end, bases)
		end)
		
		if not items_ok or not items then
			debug.error("INIT", "Failed to create base items list", items)
			vim.notify("Failed to prepare base list", vim.log.levels.ERROR)
			return false
		end
		
		debug.info("INIT", "Showing base selection UI", {items_count = #items})
		
		-- Try vim.ui.select with comprehensive error handling
		local select_ok, select_err = debug.safe_call("INIT", "show_base_selection", vim.ui.select, items, {
			prompt = "Select a base:",
			format_item = function(item)
				return item or "unknown"
			end,
		}, safe_callback)
		
		if not select_ok then
			debug.error("INIT", "Error showing base selection UI", select_err)
			vim.notify("Error showing base selection: " .. tostring(select_err), vim.log.levels.ERROR)
			
			-- Fallback: just open the first base
			if bases[1] and bases[1].path then
				debug.info("INIT", "Falling back to opening first base", bases[1])
				local fallback_ok, fallback_err = debug.safe_call("INIT", "open_fallback_base", M.open_base, bases[1].path)
				if not fallback_ok then
					debug.error("INIT", "Fallback base opening also failed", fallback_err)
					return false
				end
			else
				debug.error("INIT", "No valid base to fall back to")
				return false
			end
		end
		
		return true
	end)
	
	if list_ok then
		debug.info("INIT", "list_bases completed successfully")
		debug.exit_function("INIT", "list_bases", "success")
	else
		debug.error("INIT", "list_bases failed", result)
		debug.exit_function("INIT", "list_bases", "failed")
	end
end

return M
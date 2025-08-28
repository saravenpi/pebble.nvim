local M = {}

local parser = require("pebble.bases.parser")
local filters = require("pebble.bases.filters")
local formulas = require("pebble.bases.formulas")
local views = require("pebble.bases.views")
local cache = require("pebble.bases.cache")

local function get_root_dir()
	local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
	if vim.v.shell_error ~= 0 or git_root == "" then
		return vim.fn.getcwd()
	end
	return git_root
end

function M.open_base(base_path)
	-- Validate file path
	if not base_path or base_path == "" then
		vim.notify("No base file path provided", vim.log.levels.ERROR)
		return
	end
	
	if not vim.fn.filereadable(base_path) then
		vim.notify("Base file not found: " .. base_path, vim.log.levels.ERROR)
		return
	end
	
	-- Load base data
	local base_data, err = cache.get_base_data(base_path)
	if not base_data then
		vim.notify("Failed to load base: " .. (err or "Unknown error"), vim.log.levels.ERROR)
		return
	end
	
	-- Get file data
	local root_dir = get_root_dir()
	local files = cache.get_file_data(root_dir)
	
	if not files or #files == 0 then
		vim.notify("No markdown files found in " .. root_dir, vim.log.levels.WARN)
		views.open_base_view(base_data, {})
		return
	end
	
	
	-- Apply filters safely
	if base_data.filters then
		local ok, result = pcall(filters.filter_files, files, base_data.filters)
		if ok then
			files = result
		else
			vim.notify("Error applying filters: " .. result, vim.log.levels.ERROR)
		end
	end
	
	-- Apply view-specific filtering and ordering
	if base_data.views and #base_data.views > 0 then
		local view = base_data.views[1]
		
		if view.filters then
			local ok, result = pcall(filters.filter_files, files, view.filters)
			if ok then
				files = result
			else
				vim.notify("Error applying view filters: " .. result, vim.log.levels.ERROR)
			end
		end
		
		if view.order and #view.order > 0 then
			local ok, _ = pcall(table.sort, files, function(a, b)
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
			if not ok then
				vim.notify("Error sorting files", vim.log.levels.WARN)
			end
		end
	end
	
	-- Apply formulas safely
	if base_data.formulas then
		local ok, result = pcall(formulas.apply_formulas_to_files, files, base_data.formulas)
		if ok then
			files = result
		else
			vim.notify("Error applying formulas: " .. result, vim.log.levels.ERROR)
		end
	end
	
	-- Open the view
	views.open_base_view(base_data, files)
end

function M.open_current_base()
	local ok, err = pcall(function()
		local current_file = vim.fn.expand("%:p")
		
		if current_file:match("%.base$") then
			-- If currently in a .base file, open it
			M.open_base(current_file)
		else
			-- If not in a .base file, find and open the first available base
			local root_dir = get_root_dir()
			local bases = parser.find_base_files(root_dir)
			
			if #bases == 0 then
				vim.notify("No .base files found in " .. root_dir, vim.log.levels.WARN)
				return
			elseif #bases == 1 then
				-- Only one base file, open it directly
				vim.notify("Opening " .. bases[1].relative_path, vim.log.levels.INFO)
				M.open_base(bases[1].path)
			else
				-- Multiple bases available, open the first one by default
				vim.notify("Opening first of " .. #bases .. " available bases: " .. bases[1].relative_path .. " (use :PebbleBases to select)", vim.log.levels.INFO)
				M.open_base(bases[1].path)
			end
		end
	end)
	
	if not ok then
		vim.notify("Error in open_current_base: " .. tostring(err), vim.log.levels.ERROR)
	end
end

function M.list_bases()
	local root_dir = get_root_dir()
	local bases = parser.find_base_files(root_dir)
	
	if #bases == 0 then
		vim.notify("No .base files found in " .. root_dir, vim.log.levels.INFO)
		return
	end
	
	-- Add timeout protection for vim.ui.select
	local selection_made = false
	local function safe_callback(choice, idx)
		if selection_made then return end
		selection_made = true
		
		if choice and idx then
			local ok, err = pcall(M.open_base, bases[idx].path)
			if not ok then
				vim.notify("Error opening base: " .. tostring(err), vim.log.levels.ERROR)
			end
		end
	end
	
	-- Try vim.ui.select with protection
	local ok, err = pcall(vim.ui.select,
		vim.tbl_map(function(base) return base.relative_path end, bases),
		{
			prompt = "Select a base:",
			format_item = function(item)
				return item
			end,
		},
		safe_callback
	)
	
	if not ok then
		vim.notify("Error showing base selection: " .. tostring(err), vim.log.levels.ERROR)
		-- Fallback: just open the first base
		M.open_base(bases[1].path)
	end
end

return M
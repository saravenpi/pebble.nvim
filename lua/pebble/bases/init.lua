local M = {}

-- Simple module loading
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
	
	-- Get file data
	local root_dir = get_root_dir()
	local files = cache.get_file_data(root_dir)
	
	if not files or #files == 0 then
		vim.notify("No markdown files found in " .. root_dir, vim.log.levels.WARN)
		views.open_base_view(base_data, {})
		return
	end
	
	-- Apply base filters
	if base_data.filters then
		local ok, result = pcall(filters.filter_files, files, base_data.filters)
		if ok and result then
			files = result
		else
			vim.notify("Error applying filters", vim.log.levels.WARN)
		end
	end
	
	-- Apply view-specific filtering and ordering
	if base_data.views and #base_data.views > 0 then
		local view = base_data.views[1]
		
		-- Apply view filters
		if view.filters then
			local ok, result = pcall(filters.filter_files, files, view.filters)
			if ok and result then
				files = result
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
	
	-- Apply formulas
	if base_data.formulas and vim.tbl_count(base_data.formulas) > 0 then
		local ok, result = pcall(formulas.apply_formulas_to_files, files, base_data.formulas)
		if ok and result then
			files = result
		end
	end
	
	-- Open the view
	views.open_base_view(base_data, files)
end

function M.open_current_base()
	local current_file = vim.fn.expand("%:p")
	
	if current_file:match("%.base$") then
		-- Currently in a base file, open it
		M.open_base(current_file)
	else
		-- Find and open first available base
		local root_dir = get_root_dir()
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

function M.list_bases()
	local root_dir = get_root_dir()
	local bases = parser.find_base_files(root_dir)
	
	if #bases == 0 then
		vim.notify("No .base files found in " .. root_dir, vim.log.levels.INFO)
		return
	end
	
	-- Simple selection callback
	local function safe_callback(choice, idx)
		if choice and idx and bases[idx] then
			M.open_base(bases[idx].path)
		end
	end
	
	-- Show selection
	vim.ui.select(
		vim.tbl_map(function(base) return base.relative_path end, bases),
		{
			prompt = "Select a base:",
		},
		safe_callback
	)
end

return M
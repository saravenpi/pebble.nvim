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
	local base_data, err = cache.get_base_data(base_path)
	
	if not base_data then
		vim.notify("Failed to load base: " .. (err or "Unknown error"), vim.log.levels.ERROR)
		return
	end
	
	local root_dir = get_root_dir()
	local files = cache.get_file_data(root_dir)
	
	if base_data.filters then
		files = filters.filter_files(files, base_data.filters)
	end
	
	if #base_data.views > 0 then
		local view = base_data.views[1]
		if view.filters then
			files = filters.filter_files(files, view.filters)
		end
		
		if view.order then
			table.sort(files, function(a, b)
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
							return (a_val or "") < (b_val or "")
						else
							return (a_val or "") > (b_val or "")
						end
					end
				end
				return false
			end)
		end
	end
	
	if base_data.formulas then
		files = formulas.apply_formulas_to_files(files, base_data.formulas)
	end
	
	views.open_base_view(base_data, files)
end

function M.open_current_base()
	local current_file = vim.fn.expand("%:p")
	
	if not current_file:match("%.base$") then
		vim.notify("Current file is not a .base file", vim.log.levels.WARN)
		return
	end
	
	M.open_base(current_file)
end

function M.list_bases()
	local root_dir = get_root_dir()
	local bases = parser.find_base_files(root_dir)
	
	if #bases == 0 then
		vim.notify("No .base files found in " .. root_dir, vim.log.levels.INFO)
		return
	end
	
	vim.ui.select(
		vim.tbl_map(function(base) return base.relative_path end, bases),
		{
			prompt = "Select a base:",
			format_item = function(item)
				return item
			end,
		},
		function(choice, idx)
			if choice and idx then
				M.open_base(bases[idx].path)
			end
		end
	)
end

return M
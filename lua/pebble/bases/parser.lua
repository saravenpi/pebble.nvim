local M = {}

local search = require("pebble.bases.search")

local function parse_yaml(content)
	-- Optimized YAML parser focused on Obsidian base format
	if not content or content == "" then
		return {}
	end
	
	-- Pre-process content to remove obvious non-YAML parts for better performance
	local lines = vim.split(content, "\n")
	local result = {}
	local stack = {{obj = result, key = nil, indent = -1}}
	
	-- Performance: limit parsing to reasonable number of lines
	local max_lines = math.min(#lines, 500)
	
	for i = 1, max_lines do
		local line = lines[i]
		
		-- Skip empty lines and comments (optimized check)
		if not line or line == "" or line:match("^%s*$") or line:match("^%s*#") then
			goto continue
		end
		
		-- Fast indent calculation
		local indent_match = line:match("^(%s*)")
		local indent = indent_match and #indent_match or 0
		local trimmed = line:sub(indent + 1)
		
		-- Adjust stack based on indentation (performance optimized)
		local stack_size = #stack
		while stack_size > 1 and stack[stack_size].indent >= indent do
			stack[stack_size] = nil -- More efficient than table.remove
			stack_size = stack_size - 1
		end
		
		local current = stack[stack_size]
		
		-- Fast list item detection
		local list_prefix = trimmed:sub(1, 2)
		if list_prefix == "- " then
			-- List item (optimized processing)
			local item = trimmed:sub(3) -- Skip "- "
			if item and current.key then
				-- Ensure current container is array
				local container = current.obj[current.key]
				if type(container) ~= "table" then
					current.obj[current.key] = {}
					container = current.obj[current.key]
				end
				
				-- Fast check for nested object vs simple string
				local colon_pos = item:find(":")
				if colon_pos then
					-- It's an object in the list
					local obj = {}
					table.insert(container, obj)
					stack_size = stack_size + 1
					stack[stack_size] = {obj = obj, key = nil, indent = indent}
					
					-- Parse the first key-value pair (optimized)
					local key = item:sub(1, colon_pos - 1):gsub("^%s+", ""):gsub("%s+$", "")
					local value = item:sub(colon_pos + 1):gsub("^%s+", "")
					
					-- Fast quote removal
					if value:sub(1, 1) == '"' and value:sub(-1) == '"' then
						value = value:sub(2, -2)
					elseif value:sub(1, 1) == "'" and value:sub(-1) == "'" then
						value = value:sub(2, -2)
					end
					
					obj[key] = value == "" and {} or value
				else
					-- Simple string item (fast quote removal)
					if item:sub(1, 1) == '"' and item:sub(-1) == '"' then
						item = item:sub(2, -2)
					elseif item:sub(1, 1) == "'" and item:sub(-1) == "'" then
						item = item:sub(2, -2)
					end
					table.insert(container, item)
				end
			end
		else
			-- Check for key-value pair (optimized)
			local colon_pos = trimmed:find(":")
			if colon_pos then
				-- Key-value pair (fast extraction)
				local key = trimmed:sub(1, colon_pos - 1):gsub("^%s+", ""):gsub("%s+$", "")
				local value = trimmed:sub(colon_pos + 1):gsub("^%s+", "")
				
				if value == "" then
					-- Empty value means nested object/array
					current.obj[key] = {}
					stack_size = stack_size + 1
					stack[stack_size] = {obj = current.obj, key = key, indent = indent}
				else
					-- Fast quote removal for value
					if value:sub(1, 1) == '"' and value:sub(-1) == '"' then
						value = value:sub(2, -2)
					elseif value:sub(1, 1) == "'" and value:sub(-1) == "'" then
						value = value:sub(2, -2)
					end
					current.obj[key] = value
				end
			end
		end
		
		::continue::
	end
	
	return result
end

-- Enhanced base file parsing with performance optimizations and error recovery
function M.parse_base_file(file_path)
	if not file_path or file_path == "" then
		return nil, "No file path provided"
	end
	
	-- Check file existence and readability
	local ok, stat = pcall(vim.loop.fs_stat, file_path)
	if not ok or not stat then
		return nil, "File not found: " .. file_path
	end
	
	-- Check file size to prevent loading huge files
	if stat.size > 100000 then -- 100KB limit for base files
		return nil, "Base file too large (>100KB): " .. file_path
	end
	
	-- Safe file reading with error handling
	local read_ok, lines = pcall(vim.fn.readfile, file_path)
	if not read_ok or not lines then
		return nil, "Failed to read file: " .. file_path
	end
	
	-- Quick validation - check if it looks like YAML
	if #lines == 0 then
		return nil, "Empty base file: " .. file_path
	end
	
	local content = table.concat(lines, "\n")
	
	-- Parse YAML with error handling
	local parse_ok, base = pcall(parse_yaml, content)
	if not parse_ok then
		return nil, "YAML parsing error: " .. tostring(base)
	end
	
	if not base or type(base) ~= "table" then
		return nil, "Invalid YAML structure in: " .. file_path
	end
	
	-- Initialize default structures with validation
	base.filters = type(base.filters) == "table" and base.filters or {}
	base.formulas = type(base.formulas) == "table" and base.formulas or {}
	base.properties = type(base.properties) == "table" and base.properties or {}
	base.display = type(base.display) == "table" and base.display or base.properties or {}
	base.views = type(base.views) == "table" and base.views or {}
	
	-- Validate and fix views structure
	for i, view in ipairs(base.views) do
		if type(view) ~= "table" then
			base.views[i] = { type = "table" }
		else
			view.type = view.type or "table"
			-- Add performance limits for views
			if view.limit and tonumber(view.limit) then
				view.limit = math.min(tonumber(view.limit), 10000) -- Max 10k items
			else
				view.limit = 1000 -- Default reasonable limit
			end
		end
	end
	
	-- Add metadata for diagnostics
	base._file_path = file_path
	base._file_size = stat.size
	base._parsed_at = vim.loop.now()
	
	return base, nil
end

-- Async function for finding base files with better performance
function M.find_base_files_async(root_dir, callback)
	search.find_base_files_async(root_dir, callback)
end

-- Synchronous function for backwards compatibility
function M.find_base_files(root_dir)
	return search.find_base_files_sync(root_dir)
end

return M
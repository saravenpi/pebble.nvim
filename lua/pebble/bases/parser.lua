local M = {}

local search = require("pebble.bases.search")

local function parse_yaml(content)
	-- Simple YAML parser focused on Obsidian base format
	local lines = vim.split(content, "\n")
	local result = {}
	local stack = {{obj = result, key = nil, indent = -1}}
	
	for i, line in ipairs(lines) do
		-- Skip empty lines and comments
		if line:match("^%s*$") or line:match("^%s*#") then
			goto continue
		end
		
		local indent = #(line:match("^(%s*)"))
		local trimmed = line:gsub("^%s+", "")
		
		-- Adjust stack based on indentation
		while #stack > 1 and stack[#stack].indent >= indent do
			table.remove(stack)
		end
		
		local current = stack[#stack]
		
		if trimmed:match("^%- ") then
			-- List item
			local item = trimmed:match("^%- (.*)$")
			if item then
				-- Ensure current container is array
				if current.key then
					if type(current.obj[current.key]) ~= "table" then
						current.obj[current.key] = {}
					end
					-- Parse the list item - could be a string or object
					if item:match(":") then
						-- It's an object in the list
						local obj = {}
						table.insert(current.obj[current.key], obj)
						table.insert(stack, {obj = obj, key = nil, indent = indent})
						
						-- Parse the first key-value pair
						local key, value = item:match("^([^:]+):%s*(.*)$")
						if key and value then
							key = key:gsub("^%s+", ""):gsub("%s+$", "")
							value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
							if value == "" then
								obj[key] = {}
							else
								obj[key] = value
							end
						end
					else
						-- Simple string item
						item = item:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
						table.insert(current.obj[current.key], item)
					end
				end
			end
		elseif trimmed:match(":") then
			-- Key-value pair
			local key, value = trimmed:match("^([^:]+):%s*(.*)$")
			if key then
				key = key:gsub("^%s+", ""):gsub("%s+$", "")
				if value == "" or value == nil then
					current.obj[key] = {}
					table.insert(stack, {obj = current.obj, key = key, indent = indent})
				else
					value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
					current.obj[key] = value
				end
			end
		end
		
		::continue::
	end
	
	return result
end

function M.parse_base_file(file_path)
	if not vim.fn.filereadable(file_path) then
		return nil, "File not found: " .. file_path
	end
	
	local content = table.concat(vim.fn.readfile(file_path), "\n")
	
	local base = parse_yaml(content)
	
	if not base then
		return nil, "Failed to parse YAML"
	end
	
	base.filters = base.filters or {}
	base.formulas = base.formulas or {}
	base.properties = base.properties or {}
	base.display = base.display or base.properties or {}
	base.views = base.views or {}
	
	if type(base.views) ~= "table" then
		base.views = {}
	end
	
	for i, view in ipairs(base.views) do
		if type(view) ~= "table" then
			base.views[i] = { type = "table" }
		else
			view.type = view.type or "table"
		end
	end
	
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
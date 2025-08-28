local M = {}

local function parse_yaml(content)
	-- Try simple line-by-line parsing first (more reliable)
	local lines = vim.split(content, "\n")
	local result = {}
	local current_section = nil
	local current_list = nil
	local indent_stack = {}
	
	for i, line in ipairs(lines) do
		local original_line = line
		local leading_spaces = line:match("^(%s*)")
		local indent_level = #leading_spaces
		line = line:gsub("^%s+", "")
		
		-- Skip empty lines and comments
		if line == "" or line:match("^#") then
			goto continue
		end
		
		-- Handle root-level keys
		if indent_level == 0 then
			local key, value = line:match("^([%w_%-]+):%s*(.*)$")
			if key then
				current_section = key
				if value == "" or value == nil then
					result[key] = {}
					current_list = nil
				else
					-- Clean quotes
					value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
					result[key] = value
					current_list = nil
				end
			end
		-- Handle nested items
		elseif current_section and result[current_section] then
			if line:match("^%- ") then
				-- List item
				local value = line:match("^%- (.+)$")
				if value then
					value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
					if type(result[current_section]) ~= "table" then
						result[current_section] = {}
					end
					table.insert(result[current_section], value)
				end
			else
				-- Key-value pair in section
				local key, value = line:match("^([%w_%-%.]+):%s*(.*)$")
				if key then
					if type(result[current_section]) ~= "table" then
						result[current_section] = {}
					end
					if value == "" or value == nil then
						result[current_section][key] = {}
					else
						value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
						result[current_section][key] = value
					end
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

function M.find_base_files(root_dir)
	local bases = {}
	local cmd = string.format("find '%s' -type f -name '*.base' 2>/dev/null | head -50", root_dir)
	local result = vim.fn.system(cmd)
	
	if vim.v.shell_error == 0 then
		for path in result:gmatch("[^\n]+") do
			local name = vim.fn.fnamemodify(path, ":t:r")
			table.insert(bases, {
				name = name,
				path = path,
				relative_path = vim.fn.fnamemodify(path, ":.")
			})
		end
	end
	
	return bases
end

return M
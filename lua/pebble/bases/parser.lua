local M = {}

local function parse_yaml(content)
	local ok, yaml = pcall(function()
		return vim.fn.json_decode(vim.fn.system("python3 -c 'import sys, yaml, json; print(json.dumps(yaml.safe_load(sys.stdin.read())))'", content))
	end)
	
	if not ok then
		local lines = vim.split(content, "\n")
		local result = {}
		local current_key = nil
		local current_list = nil
		local in_list = false
		
		for _, line in ipairs(lines) do
			line = line:gsub("^%s+", "")
			
			if line ~= "" and not line:match("^#") then
				if line:match("^%- ") then
					if current_list then
						local value = line:match("^%- (.+)$")
						if value then
							value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
							table.insert(current_list, value)
						end
					end
				else
					local key, value = line:match("^([%w_%-]+):%s*(.*)$")
					if key then
						current_key = key
						if value == "" or value == nil then
							current_list = {}
							result[key] = current_list
							in_list = true
						else
							value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
							result[key] = value
							current_list = nil
							in_list = false
						end
					end
				end
			end
		end
		
		return result
	end
	
	return yaml
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
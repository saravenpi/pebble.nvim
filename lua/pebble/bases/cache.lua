local M = {}

local base_cache = {}
local file_data_cache = {}
local cache_timestamp = 0
local CACHE_TTL = 5000

local function get_markdown_files(root_dir)
	local files = {}
	local cmd = string.format("find '%s' -type f \\( -name '*.md' -o -name '*.markdown' \\) 2>/dev/null | head -200", root_dir)
	local result = vim.fn.system(cmd)
	
	if vim.v.shell_error == 0 then
		for path in result:gmatch("[^\n]+") do
			table.insert(files, path)
		end
	end
	
	return files
end

local function parse_frontmatter(file_path)
	if not vim.fn.filereadable(file_path) then
		return nil
	end
	
	local lines = vim.fn.readfile(file_path, "", 50)
	if not lines or #lines == 0 or lines[1] ~= "---" then
		return nil
	end
	
	local frontmatter = {}
	for i = 2, #lines do
		local line = lines[i]
		if line == "---" or line == "..." then
			break
		end
		
		local key, value = line:match("^([%w_%-]+):%s*(.*)$")
		if key then
			value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
			
			if value == "" and i + 1 <= #lines and lines[i + 1]:match("^%s*%- ") then
				local array_items = {}
				local j = i + 1
				while j <= #lines and lines[j]:match("^%s*%- ") do
					local item = lines[j]:match("^%s*%-%s*(.+)$")
					if item then
						item = item:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
						table.insert(array_items, item)
					end
					j = j + 1
				end
				frontmatter[key] = array_items
				i = j - 1
			else
				frontmatter[key] = value
			end
		end
	end
	
	return frontmatter
end

function M.get_file_data(root_dir, force_refresh)
	local now = vim.loop.now()
	
	if not force_refresh and file_data_cache[root_dir] and (now - cache_timestamp) < CACHE_TTL then
		return file_data_cache[root_dir]
	end
	
	local files = get_markdown_files(root_dir)
	local file_data = {}
	
	for _, path in ipairs(files) do
		local stat = vim.loop.fs_stat(path)
		if stat then
			local data = {
				path = path,
				name = vim.fn.fnamemodify(path, ":t:r"),
				ext = vim.fn.fnamemodify(path, ":e"),
				size = stat.size,
				mtime = stat.mtime.sec,
				ctime = stat.ctime.sec,
				frontmatter = parse_frontmatter(path),
			}
			
			if data.frontmatter then
				for key, value in pairs(data.frontmatter) do
					data[key] = value
				end
			end
			
			table.insert(file_data, data)
		end
	end
	
	file_data_cache[root_dir] = file_data
	cache_timestamp = now
	
	return file_data
end

function M.get_base_data(base_path, force_refresh)
	if not force_refresh and base_cache[base_path] then
		return base_cache[base_path].data, base_cache[base_path].error
	end
	
	local parser = require("pebble.bases.parser")
	local base_data, err = parser.parse_base_file(base_path)
	
	if base_data then
		base_cache[base_path] = {
			data = base_data,
			error = nil,
			timestamp = vim.loop.now()
		}
	else
		base_cache[base_path] = {
			data = nil,
			error = err,
			timestamp = vim.loop.now()
		}
	end
	
	return base_data, err
end

function M.clear_cache()
	base_cache = {}
	file_data_cache = {}
	cache_timestamp = 0
end

return M
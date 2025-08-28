local M = {}

local base_cache = {}
local file_data_cache = {}
local cache_timestamp = 0
local CACHE_TTL = 5000

local function get_markdown_files(root_dir)
	local files = {}
	-- Use find with recursive search, excluding common ignore directories
	local cmd = string.format([[find '%s' -type f \( -name '*.md' -o -name '*.markdown' \) ! -path '*/\.git/*' ! -path '*/node_modules/*' ! -path '*/\.obsidian/*' ! -path '*/build/*' ! -path '*/dist/*' 2>/dev/null]], root_dir)
	local result = vim.fn.system(cmd)
	
	if vim.v.shell_error == 0 and result ~= "" then
		for path in result:gmatch("[^\n]+") do
			if path ~= "" and vim.fn.filereadable(path) == 1 then
				table.insert(files, path)
			end
		end
	end
	
	
	-- If no files found with find, try Lua-based recursive search as fallback
	if #files == 0 then
		local function scan_dir(dir)
			-- Safely attempt to read directory
			local ok, items = pcall(vim.fn.readdir, dir)
			if not ok or not items then
				return -- Skip this directory if readdir fails
			end
			
			for _, item in ipairs(items) do
				local full_path = dir .. "/" .. item
				local stat = vim.loop.fs_stat(full_path)
				if stat then
					if stat.type == "directory" and not item:match("^%.") and item ~= "node_modules" and item ~= ".git" and item ~= ".obsidian" then
						scan_dir(full_path)
					elseif stat.type == "file" and (item:match("%.md$") or item:match("%.markdown$")) then
						table.insert(files, full_path)
					end
				end
			end
		end
		
		local ok, _ = pcall(scan_dir, root_dir)
		if not ok then
			-- If fallback also fails, return empty list
			return {}
		end
	end
	
	return files
end

local function parse_frontmatter(file_path)
	if not vim.fn.filereadable(file_path) then
		return nil
	end
	
	-- Safely read file
	local ok, lines = pcall(vim.fn.readfile, file_path, "", 50)
	if not ok or not lines or #lines == 0 or lines[1] ~= "---" then
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
		-- Safely process each file
		local ok, result = pcall(function()
			local stat = vim.loop.fs_stat(path)
			if not stat then return nil end
			
			local data = {
				path = path,
				name = vim.fn.fnamemodify(path, ":t:r"),
				ext = vim.fn.fnamemodify(path, ":e"),
				size = stat.size,
				mtime = stat.mtime.sec,
				ctime = stat.ctime.sec,
				frontmatter = parse_frontmatter(path),
			}
			
			if data.frontmatter and type(data.frontmatter) == "table" then
				for key, value in pairs(data.frontmatter) do
					data[key] = value
				end
			end
			
			return data
		end)
		
		if ok and result then
			table.insert(file_data, result)
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
local M = {}

local search = require("pebble.bases.search")

local base_cache = {}
local file_data_cache = {}
local cache_timestamp = 0
local CACHE_TTL = 5000

-- Async version for getting markdown files with better performance
local function get_markdown_files_async(root_dir, callback)
	search.find_markdown_files_async(root_dir, function(files, err)
		if err then
			-- Fallback to synchronous method
			local fallback_files = get_markdown_files_sync(root_dir)
			callback(fallback_files, nil)
		else
			callback(files or {}, nil)
		end
	end)
end

-- Synchronous fallback with optimized find command
local function get_markdown_files_sync(root_dir)
	local files = {}
	
	-- Try ripgrep first for much better performance
	if search.has_ripgrep() then
		files = search.find_markdown_files_sync(root_dir)
		if #files > 0 then
			return files
		end
	end
	
	-- Enhanced find command fallback
	local cmd = string.format([[
		find '%s' -maxdepth 5 -type f \( -name '*.md' -o -name '*.markdown' \) \
			! -path '*/\.git/*' \
			! -path '*/node_modules/*' \
			! -path '*/\.obsidian/*' \
			! -path '*/build/*' \
			! -path '*/dist/*' \
			! -path '*/target/*' \
			! -path '*/.venv/*' \
			! -path '*/.tox/*' \
			! -path '*/.next/*' \
			! -path '*/.cache/*' \
			2>/dev/null | head -n 2000
	]], root_dir)
	
	-- Use safer command execution
	local success, result = pcall(vim.fn.system, cmd)
	if success and vim.v.shell_error == 0 and result and result ~= "" then
		for path in result:gmatch("[^\n]+") do
			if path ~= "" and vim.fn.filereadable(path) == 1 then
				table.insert(files, path)
			end
		end
	end
	
	-- Ultimate fallback: limited Lua-based search if find also fails
	if #files == 0 then
		local scan_count = 0
		local MAX_SCAN_FILES = 200  -- Reasonable limit
		
		local function scan_dir(dir, depth)
			if depth > 3 or scan_count > MAX_SCAN_FILES then
				return
			end
			
			local ok, items = pcall(vim.fn.readdir, dir)
			if not ok or not items then
				return
			end
			
			-- Process files first
			for _, item in ipairs(items) do
				if scan_count > MAX_SCAN_FILES then break end
				
				local full_path = dir .. "/" .. item
				local ok_stat, stat = pcall(vim.loop.fs_stat, full_path)
				if ok_stat and stat and stat.type == "file" and 
				   (item:match("%.md$") or item:match("%.markdown$")) then
					table.insert(files, full_path)
					scan_count = scan_count + 1
				end
			end
			
			-- Then process directories (with common exclusions)
			for _, item in ipairs(items) do
				if scan_count > MAX_SCAN_FILES then break end
				
				local full_path = dir .. "/" .. item
				local ok_stat, stat = pcall(vim.loop.fs_stat, full_path)
				if ok_stat and stat and stat.type == "directory" and 
				   not item:match("^%.") and
				   item ~= "node_modules" and item ~= "build" and item ~= "dist" and
				   item ~= "target" and item ~= ".venv" and item ~= ".tox" and
				   item ~= ".next" and item ~= ".cache" then
					scan_dir(full_path, depth + 1)
				end
			end
		end
		
		local ok, _ = pcall(scan_dir, root_dir, 0)
		if not ok then
			return {}
		end
	end
	
	return files
end

-- Backwards compatibility wrapper
local function get_markdown_files(root_dir)
	return get_markdown_files_sync(root_dir)
end

local function parse_frontmatter(file_path)
	if not vim.fn.filereadable(file_path) then
		return nil
	end
	
	-- Performance: Only read first 20 lines for frontmatter parsing
	local ok, lines = pcall(vim.fn.readfile, file_path, "", 20)
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

-- Async version for better performance
function M.get_file_data_async(root_dir, force_refresh, callback)
	local now = vim.loop.now()
	
	if not force_refresh and file_data_cache[root_dir] and (now - cache_timestamp) < CACHE_TTL then
		callback(file_data_cache[root_dir], nil)
		return
	end
	
	get_markdown_files_async(root_dir, function(files, err)
		if err or not files then
			callback(nil, err or "Failed to get markdown files")
			return
		end
		
		local file_data = {}
		local max_files = math.min(#files, 500)  -- Increased limit for async processing
		local processed_count = 0
		
		-- Process files in batches to avoid blocking
		local batch_size = 20
		local current_batch = 0
		
		local function process_batch()
			local start_idx = current_batch * batch_size + 1
			local end_idx = math.min(start_idx + batch_size - 1, max_files)
			
			for i = start_idx, end_idx do
				local path = files[i]
				-- Safely process each file with better error handling
				local ok, result = pcall(function()
					local stat = vim.loop.fs_stat(path)
					if not stat then return nil end
					
					-- Skip very large files to prevent performance issues
					if stat.size > 1048576 then -- 1MB limit
						return {
							path = path,
							name = vim.fn.fnamemodify(path, ":t:r"),
							ext = vim.fn.fnamemodify(path, ":e"),
							size = stat.size,
							mtime = stat.mtime.sec,
							ctime = stat.ctime.sec,
							frontmatter = nil, -- Skip frontmatter for large files
							large_file = true
						}
					end
					
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
				processed_count = processed_count + 1
			end
			
			current_batch = current_batch + 1
			
			-- Schedule next batch or finish
			if end_idx < max_files then
				vim.schedule(process_batch)
			else
				-- All done, cache and return
				file_data_cache[root_dir] = file_data
				cache_timestamp = vim.loop.now()
				callback(file_data, nil)
			end
		end
		
		-- Start processing
		process_batch()
	end)
end

-- Synchronous version for backwards compatibility
function M.get_file_data(root_dir, force_refresh)
	local now = vim.loop.now()
	
	if not force_refresh and file_data_cache[root_dir] and (now - cache_timestamp) < CACHE_TTL then
		return file_data_cache[root_dir]
	end
	
	local files = get_markdown_files(root_dir)
	local file_data = {}
	
	-- Performance: Limit file processing to prevent freezing
	local max_files = math.min(#files, 300)  -- Increased limit but still reasonable
	
	for i = 1, max_files do
		local path = files[i]
		-- Safely process each file with better error handling
		local ok, result = pcall(function()
			local stat = vim.loop.fs_stat(path)
			if not stat then return nil end
			
			-- Skip very large files
			if stat.size > 1048576 then -- 1MB limit
				return {
					path = path,
					name = vim.fn.fnamemodify(path, ":t:r"),
					ext = vim.fn.fnamemodify(path, ":e"),
					size = stat.size,
					mtime = stat.mtime.sec,
					ctime = stat.ctime.sec,
					frontmatter = nil,
					large_file = true
				}
			end
			
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
		
		-- Yield control periodically
		if i % 20 == 0 then
			vim.schedule(function() end)  -- Yield to UI
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
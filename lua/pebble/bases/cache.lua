local M = {}

local search = require("pebble.bases.search")

-- Centralized cache management
local cache = {
	base_data = {},
	file_data = {},
	timestamps = {},
	file_mtimes = {}
}
local CACHE_TTL = 10000  -- Increased to 10 seconds for better performance

-- Check if cache is still valid by comparing file modification times
local function is_cache_valid(cache_key, file_paths)
	local now = vim.loop.now()
	local cache_time = cache.timestamps[cache_key]
	
	-- Check TTL first
	if not cache_time or (now - cache_time) > CACHE_TTL then
		return false
	end
	
	-- Check file modification times if we have file paths
	if file_paths and type(file_paths) == "table" then
		for _, path in ipairs(file_paths) do
			local ok, stat = pcall(vim.loop.fs_stat, path)
			if ok and stat then
				local cached_mtime = cache.file_mtimes[path]
				if not cached_mtime or cached_mtime ~= stat.mtime.sec then
					return false
				end
			else
				-- File doesn't exist anymore, cache is invalid
				return false
			end
		end
	end
	
	return true
end

-- Update cache timestamps and file mtimes
local function update_cache_metadata(cache_key, file_paths)
	cache.timestamps[cache_key] = vim.loop.now()
	
	if file_paths and type(file_paths) == "table" then
		for _, path in ipairs(file_paths) do
			local ok, stat = pcall(vim.loop.fs_stat, path)
			if ok and stat then
				cache.file_mtimes[path] = stat.mtime.sec
			end
		end
	end
end

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
	local cache_key = "file_data_" .. root_dir
	
	-- Check cache validity
	if not force_refresh and cache.file_data[cache_key] and is_cache_valid(cache_key, nil) then
		callback(cache.file_data[cache_key], nil)
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
				cache.file_data[cache_key] = file_data
				update_cache_metadata(cache_key, files)
				callback(file_data, nil)
			end
		end
		
		-- Start processing
		process_batch()
	end)
end

-- Synchronous version for backwards compatibility
function M.get_file_data(root_dir, force_refresh)
	local cache_key = "file_data_" .. root_dir
	
	-- Check cache validity
	if not force_refresh and cache.file_data[cache_key] and is_cache_valid(cache_key, nil) then
		return cache.file_data[cache_key]
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
	
	cache.file_data[cache_key] = file_data
	update_cache_metadata(cache_key, files)
	
	return file_data
end

function M.get_base_data(base_path, force_refresh)
	local cache_key = "base_data_" .. base_path
	
	-- Check cache validity with file modification time
	if not force_refresh and cache.base_data[cache_key] and is_cache_valid(cache_key, {base_path}) then
		return cache.base_data[cache_key].data, cache.base_data[cache_key].error
	end
	
	local parser = require("pebble.bases.parser")
	local base_data, err = parser.parse_base_file(base_path)
	
	if base_data then
		cache.base_data[cache_key] = {
			data = base_data,
			error = nil
		}
	else
		cache.base_data[cache_key] = {
			data = nil,
			error = err
		}
	end
	
	update_cache_metadata(cache_key, {base_path})
	
	return base_data, err
end

-- Enhanced cache clearing with selective options
function M.clear_cache(cache_type)
	if cache_type == "base" then
		cache.base_data = {}
	elseif cache_type == "files" then
		cache.file_data = {}
		cache.file_mtimes = {}
	else
		-- Clear all caches
		cache.base_data = {}
		cache.file_data = {}
		cache.timestamps = {}
		cache.file_mtimes = {}
	end
	
	-- Also clear content cache from filters
	local filters = require("pebble.bases.filters")
	pcall(filters.clear_content_cache)
	
	-- Clear search cache
	local search = require("pebble.bases.search")
	pcall(search.clear_cache)
end

-- Get cache statistics for debugging
function M.get_cache_stats()
	return {
		base_data_entries = vim.tbl_count(cache.base_data),
		file_data_entries = vim.tbl_count(cache.file_data),
		timestamps = vim.tbl_count(cache.timestamps),
		file_mtimes = vim.tbl_count(cache.file_mtimes),
		ttl = CACHE_TTL
	}
end

return M
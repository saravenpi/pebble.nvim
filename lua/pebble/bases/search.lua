local M = {}

-- Configuration for ripgrep with optimized settings
local config = {
	ripgrep_path = "rg",
	max_files = 5000, -- Increased for better coverage
	max_depth = 15, -- Allow deeper traversal
	timeout = 45000, -- 45 seconds for large repos
	max_filesize = "10M", -- Skip files larger than 10MB
	exclude_patterns = {
		".git",
		"node_modules",
		".obsidian", 
		"build",
		"dist",
		"target",
		".venv",
		".tox",
		".next",
		".cache",
		"*.lock",
		"*.tmp",
		"*.log",
		"coverage",
		"__pycache__"
	},
	-- Ripgrep performance optimization flags
	rg_common_flags = {
		"--no-config", -- Don't load user config files
		"--threads", "4", -- Limit threads for stability
		"--max-columns", "1000", -- Prevent extremely long lines
		"--max-filesize", "10M", -- Skip large files
		"--smart-case", -- Smart case matching
		"--follow", -- Follow symlinks
		"--hidden" -- Include hidden files (except those in .gitignore)
	}
}

-- Enhanced caching system
local rg_cache = {}
local RG_CACHE_TTL = 30000 -- 30 seconds for better performance
local RG_MAX_CACHE_SIZE = 1000 -- Limit cache size
local cache_stats = { hits = 0, misses = 0, evictions = 0 }

-- Enhanced cache management with LRU-style eviction
local function manage_cache()
	local now = vim.loop.now()
	local cache_size = 0
	local expired_keys = {}
	
	-- Count cache size and collect expired entries
	for key, entry in pairs(rg_cache) do
		cache_size = cache_size + 1
		if (now - entry.timestamp) > RG_CACHE_TTL then
			table.insert(expired_keys, key)
		end
	end
	
	-- Remove expired entries
	for _, key in ipairs(expired_keys) do
		rg_cache[key] = nil
		cache_stats.evictions = cache_stats.evictions + 1
	end
	
	-- If still over limit, remove oldest entries
	local remaining_size = cache_size - #expired_keys
	if remaining_size > RG_MAX_CACHE_SIZE then
		local entries = {}
		for key, entry in pairs(rg_cache) do
			table.insert(entries, { key = key, timestamp = entry.timestamp })
		end
		
		-- Sort by timestamp (oldest first)
		table.sort(entries, function(a, b) return a.timestamp < b.timestamp end)
		
		-- Remove oldest entries
		local to_remove = remaining_size - RG_MAX_CACHE_SIZE + 100 -- Remove extra for buffer
		for i = 1, math.min(to_remove, #entries) do
			rg_cache[entries[i].key] = nil
			cache_stats.evictions = cache_stats.evictions + 1
		end
	end
end

-- Async wrapper for vim.system (Neovim 0.10+) with fallback
local function run_command_async(cmd, opts, callback)
	if vim.system then
		-- Use modern vim.system API
		opts = opts or {}
		opts.timeout = opts.timeout or config.timeout
		
		vim.system(cmd, opts, function(result)
			vim.schedule(function()
				callback(result.code == 0, result.stdout or "", result.stderr or "")
			end)
		end)
	else
		-- Fallback to vim.fn.jobstart for older Neovim
		local stdout = {}
		local stderr = {}
		
		local job_id = vim.fn.jobstart(cmd, {
			on_stdout = function(_, data)
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(stdout, line)
					end
				end
			end,
			on_stderr = function(_, data)
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(stderr, line)
					end
				end
			end,
			on_exit = function(_, code)
				vim.schedule(function()
					callback(code == 0, table.concat(stdout, "\n"), table.concat(stderr, "\n"))
				end)
			end,
		})
		
		if job_id <= 0 then
			callback(false, "", "Failed to start job")
		end
	end
end

-- Build optimized ripgrep command with proper escaping and performance flags
local function build_ripgrep_cmd(pattern, root_dir, options)
	options = options or {}
	local cmd = { config.ripgrep_path }
	
	-- Add common performance flags first
	for _, flag in ipairs(config.rg_common_flags) do
		table.insert(cmd, flag)
	end
	
	-- Add type definitions for custom file types
	table.insert(cmd, "--type-add")
	table.insert(cmd, "base:*.base")
	table.insert(cmd, "--type-add") 
	table.insert(cmd, "markdown:*.{md,markdown}")
	
	-- Configure output options
	if options.files_only then
		table.insert(cmd, "--files")
	else
		table.insert(cmd, "--with-filename")
		table.insert(cmd, "--line-number")
	end
	
	-- Add search options
	if options.case_insensitive then
		table.insert(cmd, "--ignore-case")
	end
	
	if options.count_only then
		table.insert(cmd, "--count")
	end
	
	if options.files_with_matches then
		table.insert(cmd, "--files-with-matches")
	end
	
	if options.max_count then
		table.insert(cmd, "--max-count")
		table.insert(cmd, tostring(options.max_count))
	end
	
	if options.max_depth and options.max_depth > 0 then
		table.insert(cmd, "--max-depth")
		table.insert(cmd, tostring(options.max_depth))
	end
	
	-- Add file type restrictions with optimizations
	if options.file_type then
		table.insert(cmd, "--type")
		table.insert(cmd, options.file_type)
	elseif options.glob_pattern then
		-- Support multiple glob patterns
		if type(options.glob_pattern) == "table" then
			for _, pattern in ipairs(options.glob_pattern) do
				table.insert(cmd, "--glob")
				table.insert(cmd, pattern)
			end
		else
			table.insert(cmd, "--glob")
			table.insert(cmd, options.glob_pattern)
		end
	end
	
	-- Add exclude patterns efficiently 
	for _, exclude in ipairs(config.exclude_patterns) do
		table.insert(cmd, "--glob")
		table.insert(cmd, "!" .. exclude)
		table.insert(cmd, "--glob")
		table.insert(cmd, "!**/" .. exclude .. "/**") -- Also exclude subdirectories
	end
	
	-- Add custom excludes from options
	if options.exclude then
		for _, exclude in ipairs(options.exclude) do
			table.insert(cmd, "--glob")
			table.insert(cmd, "!" .. exclude)
		end
	end
	
	-- Add pattern with proper escaping
	if pattern and not options.files_only then
		-- Use fixed-string mode for better performance when appropriate
		if options.fixed_strings then
			table.insert(cmd, "--fixed-strings")
		end
		table.insert(cmd, "--")
		table.insert(cmd, pattern)
	end
	
	-- Add root directory (ensure it's properly quoted)
	table.insert(cmd, root_dir)
	
	return cmd
end

-- Enhanced synchronous ripgrep wrapper with better error handling
local function run_ripgrep_sync(pattern, root_dir, options)
	local cmd = build_ripgrep_cmd(pattern, root_dir, options)
	
	-- Use vim.system if available for better performance
	if vim.system then
		local result = vim.system(cmd, { timeout = config.timeout, text = true }):wait()
		
		if result.code == 127 or result.code == 2 then
			return nil, "ripgrep not found, please install ripgrep"
		elseif result.code ~= 0 and result.code ~= 1 then -- Code 1 is "no matches found", not an error
			return nil, "ripgrep command failed with code " .. result.code .. ": " .. (result.stderr or "")
		end
		
		local files = {}
		if result.stdout then
			for path in result.stdout:gmatch("[^\n]+") do
				if path ~= "" then
					table.insert(files, path)
				end
			end
		end
		
		return files, nil
	else
		-- Fallback to vim.fn.system
		local cmd_str = vim.fn.shelljoin(cmd) -- Proper shell escaping
		local result = vim.fn.system(cmd_str .. " 2>/dev/null")
		
		if vim.v.shell_error == 127 or vim.v.shell_error == 2 then
			return nil, "ripgrep not found, please install ripgrep"
		elseif vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
			return nil, "ripgrep command failed with code " .. vim.v.shell_error
		end
		
		local files = {}
		for path in result:gmatch("[^\n]+") do
			if path ~= "" then
				table.insert(files, path)
			end
		end
		
		return files, nil
	end
end

-- Optimized async function to find base files
function M.find_base_files_async(root_dir, callback)
	if not M.has_ripgrep() then
		-- Use optimized fallback
		vim.schedule(function()
			local result, err = M.find_base_files_fallback(root_dir)
			callback(result, err)
		end)
		return
	end
	
	-- Check cache first with hit tracking
	local cache_key = "base_files_" .. vim.fn.fnamemodify(root_dir, ":p") -- Normalize path
	local cached = rg_cache[cache_key]
	local now = vim.loop.now()
	
	if cached and (now - cached.timestamp) < RG_CACHE_TTL then
		cache_stats.hits = cache_stats.hits + 1
		-- Update access time for LRU
		cached.last_access = now
		callback(cached.data, cached.error)
		return
	end
	
	cache_stats.misses = cache_stats.misses + 1
	
	local cmd = build_ripgrep_cmd(nil, root_dir, {
		files_only = true,
		file_type = "base",
		max_depth = config.max_depth,
		fixed_strings = false -- Pattern-based search for file extensions
	})
	
	run_command_async(cmd, {}, function(success, stdout, stderr)
		local bases = {}
		local error_msg = nil
		
		if success then
			local count = 0
			for path in stdout:gmatch("[^\n]+") do
				if path ~= "" then
					count = count + 1
					if count > 1000 then break end -- Increased limit for async
					
					local name = vim.fn.fnamemodify(path, ":t:r")
					table.insert(bases, {
						name = name,
						path = path,
						relative_path = vim.fn.fnamemodify(path, ":."),
						file_size = vim.fn.getfsize(path)
					})
				end
			end
		else
			error_msg = "ripgrep failed: " .. (stderr or "unknown error")
		end
		
		-- Cache the result with access tracking
		manage_cache() -- Clean up cache before adding new entry
		rg_cache[cache_key] = {
			data = bases,
			error = error_msg,
			timestamp = vim.loop.now(),
			last_access = vim.loop.now()
		}
		
		callback(bases, error_msg)
	end)
end

-- Optimized synchronous version with smart fallbacks
function M.find_base_files_sync(root_dir)
	local bases = {}
	
	if not M.has_ripgrep() then
		return M.find_base_files_fallback(root_dir)
	end
	
	local files, err = run_ripgrep_sync(nil, root_dir, {
		files_only = true,
		file_type = "base",
		max_depth = config.max_depth
	})
	
	if err then
		return M.find_base_files_fallback(root_dir)
	end
	
	local count = 0
	for _, path in ipairs(files) do
		count = count + 1
		if count > 1000 then break end -- Increased limit
		
		local name = vim.fn.fnamemodify(path, ":t:r")
		table.insert(bases, {
			name = name,
			path = path,
			relative_path = vim.fn.fnamemodify(path, ":"),
			file_size = vim.fn.getfsize(path)
		})
	end
	
	return bases
end

-- Optimized fallback for when ripgrep is not available
function M.find_base_files_fallback(root_dir)
	local bases = {}
	
	-- Enhanced find command with better exclusions
	local excludes = {}
	for _, exclude in ipairs(config.exclude_patterns) do
		table.insert(excludes, "-not -path '*" .. exclude .. "*'")
	end
	
	local exclude_str = table.concat(excludes, " ")
	local cmd = string.format("find '%s' -type f -name '*.base' %s 2>/dev/null | head -1000", 
		root_dir, exclude_str)
	
	local success, result = pcall(vim.fn.system, cmd)
	if success and vim.v.shell_error == 0 and result then
		for path in result:gmatch("[^\n]+") do
			if path ~= "" and vim.fn.filereadable(path) == 1 then
				local name = vim.fn.fnamemodify(path, ":t:r")
				table.insert(bases, {
					name = name,
					path = path,
					relative_path = vim.fn.fnamemodify(path, ":"),
					file_size = vim.fn.getfsize(path)
				})
			end
		end
	end
	
	return bases, nil
end

-- Maintain backwards compatibility 
function M.find_base_files_rg(root_dir)
	return M.find_base_files_sync(root_dir)
end

-- Async function to find markdown files
function M.find_markdown_files_async(root_dir, callback)
	if not M.has_ripgrep() then
		-- Fallback to synchronous method
		vim.schedule(function()
			local result = M.find_markdown_files_sync(root_dir)
			callback(result, nil)
		end)
		return
	end
	
	-- Check cache first
	local cache_key = "md_files_" .. root_dir
	local cached = rg_cache[cache_key]
	local now = vim.loop.now()
	
	if cached and (now - cached.timestamp) < RG_CACHE_TTL then
		callback(cached.data, cached.error)
		return
	end
	
	local cmd = build_ripgrep_cmd(nil, root_dir, {
		files_only = true,
		file_type = "markdown", -- Use the type we defined
		max_depth = config.max_depth
	})
	
	run_command_async(cmd, {}, function(success, stdout, stderr)
		local files = {}
		local error_msg = nil
		
		if success then
			local count = 0
			for path in stdout:gmatch("[^\n]+") do
				if path ~= "" then
					count = count + 1
					if count > config.max_files then break end
					table.insert(files, path)
				end
			end
		else
			error_msg = "ripgrep failed: " .. (stderr or "unknown error")
		end
		
		-- Cache the result
		rg_cache[cache_key] = {
			data = files,
			error = error_msg,
			timestamp = vim.loop.now()
		}
		
		callback(files, error_msg)
	end)
end

-- Synchronous version for backwards compatibility
function M.find_markdown_files_sync(root_dir)
	local files = {}
	
	if not M.has_ripgrep() then
		-- Use find as fallback
		local cmd = string.format("find '%s' -type f \\( -name '*.md' -o -name '*.markdown' \\) -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.obsidian/*' 2>/dev/null | head -%d", root_dir, config.max_files)
		local result = vim.fn.system(cmd)
		
		if vim.v.shell_error == 0 then
			for path in result:gmatch("[^\n]+") do
				if path ~= "" then
					table.insert(files, path)
				end
			end
		end
		return files
	end
	
	local paths, err = run_ripgrep_sync(nil, root_dir, {
		files_only = true,
		file_type = "markdown",
		max_depth = config.max_depth
	})
	
	if err then
		-- Fallback to find
		local cmd = string.format("find '%s' -type f \\( -name '*.md' -o -name '*.markdown' \\) -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.obsidian/*' 2>/dev/null | head -%d", root_dir, config.max_files)
		local result = vim.fn.system(cmd)
		
		if vim.v.shell_error == 0 then
			for path in result:gmatch("[^\n]+") do
				if path ~= "" then
					table.insert(files, path)
				end
			end
		end
		return files
	end
	
	local count = 0
	for _, path in ipairs(paths) do
		count = count + 1
		if count > config.max_files then break end
		table.insert(files, path)
	end
	
	return files
end

-- Maintain backwards compatibility
function M.find_markdown_files_rg(root_dir)
	return M.find_markdown_files_sync(root_dir)
end

-- Async search in files with comprehensive options
function M.search_in_files_async(pattern, root_dir, options, callback)
	if not M.has_ripgrep() then
		callback(nil, "ripgrep not found, please install ripgrep")
		return
	end
	
	options = options or {}
	
	-- Check cache first if enabled
	if not options.no_cache then
		local cache_key = "search_" .. pattern .. "_" .. root_dir .. "_" .. vim.inspect(options)
		local cached = rg_cache[cache_key]
		local now = vim.loop.now()
		
		if cached and (now - cached.timestamp) < RG_CACHE_TTL then
			callback(cached.data, cached.error)
			return
		end
		
		-- Clean expired cache entries
		clear_expired_cache()
	end
	
	local cmd = build_ripgrep_cmd(pattern, root_dir, options)
	
	run_command_async(cmd, {}, function(success, stdout, stderr)
		local matches = {}
		local error_msg = nil
		
		if success then
			local count = 0
			for line in stdout:gmatch("[^\n]+") do
				if line ~= "" then
					count = count + 1
					if options.max_results and count > options.max_results then
						break
					end
					table.insert(matches, line)
				end
			end
		else
			error_msg = "ripgrep failed: " .. (stderr or "unknown error")
		end
		
		-- Cache the result if caching is enabled
		if not options.no_cache then
			local cache_key = "search_" .. pattern .. "_" .. root_dir .. "_" .. vim.inspect(options)
			rg_cache[cache_key] = {
				data = matches,
				error = error_msg,
				timestamp = vim.loop.now()
			}
		end
		
		callback(matches, error_msg)
	end)
end

-- Synchronous search for backwards compatibility
function M.search_in_files(pattern, root_dir, options)
	if not M.has_ripgrep() then
		return nil, "ripgrep not found, please install ripgrep"
	end
	
	options = options or {}
	local matches, err = run_ripgrep_sync(pattern, root_dir, options)
	
	if err then
		return nil, err
	end
	
	-- Apply result limits
	if options.max_results and #matches > options.max_results then
		local limited = {}
		for i = 1, options.max_results do
			table.insert(limited, matches[i])
		end
		return limited, nil
	end
	
	return matches, nil
end

-- Highly optimized tag extraction using ripgrep
function M.extract_tags_async(root_dir, callback)
	if not M.has_ripgrep() then
		M.extract_tags_fallback(root_dir, callback)
		return
	end
	
	-- Check cache first
	local cache_key = "tags_" .. root_dir
	local cached = rg_cache[cache_key]
	local now = vim.loop.now()
	
	if cached and (now - cached.timestamp) < RG_CACHE_TTL then
		callback(cached.data, cached.error)
		return
	end
	
	-- Search for hashtags with optimized pattern
	local cmd = build_ripgrep_cmd("#[a-zA-Z0-9_-]+", root_dir, {
		file_type = "markdown",
		files_with_matches = false,
		max_count = 2000, -- Increased limit
		fixed_strings = false -- Use regex for tag matching
	})
	
	run_command_async(cmd, {}, function(success, stdout, stderr)
		local tags = {}
		local error_msg = nil
		
		if success then
			for line in stdout:gmatch("[^\n]+") do
				for tag in line:gmatch("#([a-zA-Z0-9_-]+)") do
					if not tags[tag] then
						tags[tag] = 0
					end
					tags[tag] = tags[tag] + 1
				end
			end
		else
			error_msg = "Failed to extract tags: " .. (stderr or "unknown error")
		end
		
		-- Cache the result
		rg_cache[cache_key] = {
			data = tags,
			error = error_msg,
			timestamp = vim.loop.now()
		}
		
		callback(tags, error_msg)
	end)
end

function M.extract_links_async(root_dir, callback)
	if not M.has_ripgrep() then
		M.extract_links_fallback(root_dir, callback)
		return
	end
	
	-- Check cache first
	local cache_key = "links_" .. root_dir
	local cached = rg_cache[cache_key]
	local now = vim.loop.now()
	
	if cached and (now - cached.timestamp) < RG_CACHE_TTL then
		callback(cached.data, cached.error)
		return
	end
	
	-- Search for obsidian links with better pattern
	local cmd = build_ripgrep_cmd("\\[\\[[^\\]]+\\]\\]", root_dir, {
		file_type = "markdown",
		files_with_matches = false,
		max_count = 5000, -- Much higher limit for link extraction
		fixed_strings = false -- Use regex for link matching
	})
	
	run_command_async(cmd, {}, function(success, stdout, stderr)
		local links = {}
		local error_msg = nil
		
		if success then
			for line in stdout:gmatch("[^\n]+") do
				-- Extract file path and line content
				local file_path, line_num, content = line:match("^([^:]+):(%d+):(.+)")
				if file_path and content then
					for link in content:gmatch("%[%[([^%]]+)%]%]") do
						if not links[link] then
							links[link] = {}
						end
						table.insert(links[link], {
							file = file_path,
							line = tonumber(line_num)
						})
					end
				end
			end
		else
			error_msg = "Failed to extract links: " .. (stderr or "unknown error")
		end
		
		-- Cache the result
		rg_cache[cache_key] = {
			data = links,
			error = error_msg,
			timestamp = vim.loop.now()
		}
		
		callback(links, error_msg)
	end)
end

-- Configuration functions
function M.setup(opts)
	if opts then
		config = vim.tbl_deep_extend("force", config, opts)
	end
end

function M.get_config()
	return vim.deepcopy(config)
end

-- Enhanced cache management
function M.clear_cache()
	rg_cache = {}
	cache_stats = { hits = 0, misses = 0, evictions = 0 }
end

function M.get_cache_stats()
	return {
		entries = vim.tbl_count(rg_cache),
		ttl = RG_CACHE_TTL,
		max_size = RG_MAX_CACHE_SIZE,
		hits = cache_stats.hits,
		misses = cache_stats.misses,
		evictions = cache_stats.evictions,
		hit_rate = cache_stats.hits > 0 and (cache_stats.hits / (cache_stats.hits + cache_stats.misses)) * 100 or 0
	}
end

-- Advanced search with multiple patterns
function M.search_multiple_patterns_async(patterns, root_dir, options, callback)
	if not M.has_ripgrep() then
		callback(nil, "ripgrep not found")
		return
	end
	
	options = options or {}
	local results = {}
	local completed = 0
	local total = #patterns
	
	for i, pattern in ipairs(patterns) do
		M.search_in_files_async(pattern, root_dir, options, function(matches, err)
			if matches then
				results[pattern] = matches
			else
				results[pattern] = {}
			end
			
			completed = completed + 1
			if completed == total then
				callback(results, nil)
			end
		end)
	end
end

-- Batch file operations for better performance
function M.batch_file_operations_async(operations, callback)
	local results = {}
	local completed = 0
	local total = #operations
	
	for i, op in ipairs(operations) do
		if op.type == "find_base_files" then
			M.find_base_files_async(op.root_dir, function(data, err)
				results[i] = { data = data, error = err }
				completed = completed + 1
				if completed == total then callback(results) end
			end)
		elseif op.type == "find_markdown_files" then
			M.find_markdown_files_async(op.root_dir, function(data, err)
				results[i] = { data = data, error = err }
				completed = completed + 1
				if completed == total then callback(results) end
			end)
		elseif op.type == "search" then
			M.search_in_files_async(op.pattern, op.root_dir, op.options, function(data, err)
				results[i] = { data = data, error = err }
				completed = completed + 1
				if completed == total then callback(results) end
			end)
		else
			results[i] = { data = nil, error = "Unknown operation type: " .. (op.type or "nil") }
			completed = completed + 1
			if completed == total then callback(results) end
		end
	end
end

-- Enhanced utility functions with caching
local ripgrep_available = nil
local ripgrep_version_cache = nil

-- Centralized git root detection with caching
local _git_root_cache = nil
local _git_root_cache_time = 0
local GIT_ROOT_CACHE_TTL = 30000  -- 30 seconds

function M.get_root_dir()
	local now = vim.loop.now()
	-- Use cached git root if still valid
	if _git_root_cache and (now - _git_root_cache_time) < GIT_ROOT_CACHE_TTL then
		return _git_root_cache
	end
	
	-- Try to get git root using vim.system if available for better performance
	local git_root
	if vim.system then
		local result = vim.system({"git", "rev-parse", "--show-toplevel"}, { 
			timeout = 5000,
			text = true,
			cwd = vim.fn.getcwd()
		}):wait()
		
		if result.code == 0 and result.stdout then
			git_root = vim.trim(result.stdout)
		end
	else
		git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
	end
	
	local root_dir
	if not git_root or git_root == "" or (vim.v.shell_error and vim.v.shell_error ~= 0) then
		root_dir = vim.fn.getcwd()
	else
		root_dir = git_root
	end
	
	-- Cache the result
	_git_root_cache = root_dir
	_git_root_cache_time = now
	return root_dir
end

function M.has_ripgrep()
	if ripgrep_available ~= nil then
		return ripgrep_available
	end
	
	-- Check multiple possible locations for ripgrep
	local possible_paths = { config.ripgrep_path, "rg", "/usr/local/bin/rg", "/opt/homebrew/bin/rg" }
	
	for _, rg_path in ipairs(possible_paths) do
		local result = vim.fn.system("which " .. rg_path .. " 2>/dev/null")
		if vim.v.shell_error == 0 and result ~= "" then
			config.ripgrep_path = rg_path -- Update config with working path
			ripgrep_available = true
			return true
		end
	end
	
	ripgrep_available = false
	return false
end

function M.get_ripgrep_version()
	if ripgrep_version_cache then
		return ripgrep_version_cache
	end
	
	if not M.has_ripgrep() then
		return nil
	end
	
	local result = vim.fn.system(config.ripgrep_path .. " --version 2>/dev/null")
	local version = result:match("ripgrep ([%d%.]+)")
	ripgrep_version_cache = version
	return version
end

-- Fallback tag extraction when ripgrep is not available
function M.extract_tags_fallback(root_dir, callback)
	vim.schedule(function()
		local tags = {}
		
		-- Use basic find + grep fallback
		local cmd = string.format(
			"find '%s' -name '*.md' -o -name '*.markdown' | head -500 | xargs grep -h '#[a-zA-Z0-9_-]\\+' 2>/dev/null || true",
			root_dir
		)
		
		local success, result = pcall(vim.fn.system, cmd)
		if success and result then
			for line in result:gmatch("[^\n]+") do
				for tag in line:gmatch("#([a-zA-Z0-9_-]+)") do
					if not tags[tag] then
						tags[tag] = 0
					end
					tags[tag] = tags[tag] + 1
				end
			end
		end
		
		callback(tags, nil)
	end)
end

-- Fallback link extraction when ripgrep is not available
function M.extract_links_fallback(root_dir, callback)
	vim.schedule(function()
		local links = {}
		
		-- Use basic find + grep fallback
		local cmd = string.format(
			"find '%s' -name '*.md' -o -name '*.markdown' | head -500 | xargs grep -Hn '\\[\\[[^\\]]*\\]\\]' 2>/dev/null || true",
			root_dir
		)
		
		local success, result = pcall(vim.fn.system, cmd)
		if success and result then
			for line in result:gmatch("[^\n]+") do
				local file_path, line_num, content = line:match("^([^:]+):(%d+):(.+)")
				if file_path and content then
					for link in content:gmatch("%[%[([^%]]+)%]%]") do
						if not links[link] then
							links[link] = {}
						end
						table.insert(links[link], {
							file = file_path,
							line = tonumber(line_num)
						})
					end
				end
			end
		end
		
		callback(links, nil)
	end)
end

return M
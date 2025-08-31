local M = {}

-- Configuration for ripgrep
local config = {
	ripgrep_path = "rg",
	max_files = 2000,
	max_depth = 10,
	timeout = 30000, -- 30 seconds
	exclude_patterns = {
		".git",
		"node_modules",
		".obsidian",
		"build",
		"dist",
		"target",
		".venv",
		".tox",
		"*.lock",
		"*.tmp"
	}
}

-- Cache for ripgrep results
local rg_cache = {}
local RG_CACHE_TTL = 10000 -- 10 seconds

local function clear_expired_cache()
	local now = vim.loop.now()
	for key, entry in pairs(rg_cache) do
		if (now - entry.timestamp) > RG_CACHE_TTL then
			rg_cache[key] = nil
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

-- Build ripgrep command with proper error handling and escaping
local function build_ripgrep_cmd(pattern, root_dir, options)
	options = options or {}
	local cmd = { config.ripgrep_path }
	
	-- Add type definitions for custom file types
	table.insert(cmd, "--type-add")
	table.insert(cmd, "base:*.base")
	
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
	
	-- Add file type restrictions
	if options.file_type then
		table.insert(cmd, "--type")
		table.insert(cmd, options.file_type)
	elseif options.glob_pattern then
		table.insert(cmd, "--glob")
		table.insert(cmd, options.glob_pattern)
	end
	
	-- Add exclude patterns
	for _, exclude in ipairs(config.exclude_patterns) do
		table.insert(cmd, "--glob")
		table.insert(cmd, "!" .. exclude)
	end
	
	-- Add custom excludes from options
	if options.exclude then
		for _, exclude in ipairs(options.exclude) do
			table.insert(cmd, "--glob")
			table.insert(cmd, "!" .. exclude)
		end
	end
	
	-- Add pattern if searching content (not just files)
	if pattern and not options.files_only then
		table.insert(cmd, "--")
		table.insert(cmd, pattern)
	end
	
	-- Add root directory
	table.insert(cmd, root_dir)
	
	return cmd
end

-- Synchronous ripgrep wrapper for backwards compatibility
local function run_ripgrep_sync(pattern, root_dir, options)
	local cmd = build_ripgrep_cmd(pattern, root_dir, options)
	
	local cmd_str = table.concat(cmd, " ")
	local result = vim.fn.system(cmd_str .. " 2>/dev/null")
	
	if vim.v.shell_error == 127 or vim.v.shell_error == 2 then
		return nil, "ripgrep not found, please install ripgrep"
	elseif vim.v.shell_error ~= 0 then
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

-- Async function to find base files
function M.find_base_files_async(root_dir, callback)
	if not M.has_ripgrep() then
		-- Fallback to synchronous method
		vim.schedule(function()
			local result = M.find_base_files_sync(root_dir)
			callback(result, nil)
		end)
		return
	end
	
	-- Check cache first
	local cache_key = "base_files_" .. root_dir
	local cached = rg_cache[cache_key]
	local now = vim.loop.now()
	
	if cached and (now - cached.timestamp) < RG_CACHE_TTL then
		callback(cached.data, cached.error)
		return
	end
	
	local cmd = build_ripgrep_cmd(nil, root_dir, {
		files_only = true,
		file_type = "base",
		max_depth = config.max_depth
	})
	
	run_command_async(cmd, {}, function(success, stdout, stderr)
		local bases = {}
		local error_msg = nil
		
		if success then
			local count = 0
			for path in stdout:gmatch("[^\n]+") do
				if path ~= "" then
					count = count + 1
					if count > 100 then break end -- Reasonable limit
					
					local name = vim.fn.fnamemodify(path, ":t:r")
					table.insert(bases, {
						name = name,
						path = path,
						relative_path = vim.fn.fnamemodify(path, ":.")
					})
				end
			end
		else
			error_msg = "ripgrep failed: " .. (stderr or "unknown error")
		end
		
		-- Cache the result
		rg_cache[cache_key] = {
			data = bases,
			error = error_msg,
			timestamp = vim.loop.now()
		}
		
		callback(bases, error_msg)
	end)
end

-- Synchronous version for backwards compatibility
function M.find_base_files_sync(root_dir)
	local bases = {}
	
	if not M.has_ripgrep() then
		-- Use find as fallback
		local cmd = string.format("find '%s' -type f -name '*.base' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | head -100", root_dir)
		local result = vim.fn.system(cmd)
		
		if vim.v.shell_error == 0 then
			for path in result:gmatch("[^\n]+") do
				if path ~= "" then
					local name = vim.fn.fnamemodify(path, ":t:r")
					table.insert(bases, {
						name = name,
						path = path,
						relative_path = vim.fn.fnamemodify(path, ":.")
					})
				end
			end
		end
		return bases
	end
	
	local files, err = run_ripgrep_sync(nil, root_dir, {
		files_only = true,
		file_type = "base",
		max_depth = config.max_depth
	})
	
	if err then
		-- Fallback to find
		local cmd = string.format("find '%s' -type f -name '*.base' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | head -100", root_dir)
		local result = vim.fn.system(cmd)
		
		if vim.v.shell_error == 0 then
			for path in result:gmatch("[^\n]+") do
				if path ~= "" then
					local name = vim.fn.fnamemodify(path, ":t:r")
					table.insert(bases, {
						name = name,
						path = path,
						relative_path = vim.fn.fnamemodify(path, ":.")
					})
				end
			end
		end
		return bases
	end
	
	local count = 0
	for _, path in ipairs(files) do
		count = count + 1
		if count > 100 then break end
		
		local name = vim.fn.fnamemodify(path, ":t:r")
		table.insert(bases, {
			name = name,
			path = path,
			relative_path = vim.fn.fnamemodify(path, ":.")
		})
	end
	
	return bases
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
		glob_pattern = "*.{md,markdown}",
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
		glob_pattern = "*.{md,markdown}",
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

-- Enhanced tag and link extraction using ripgrep
function M.extract_tags_async(root_dir, callback)
	if not M.has_ripgrep() then
		callback(nil, "ripgrep not found")
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
	
	-- Search for hashtags pattern
	local cmd = build_ripgrep_cmd("#[a-zA-Z0-9_-]+", root_dir, {
		file_type = "md",
		files_with_matches = false,
		max_count = 1000
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
		callback(nil, "ripgrep not found")
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
	
	-- Search for obsidian links pattern
	local cmd = build_ripgrep_cmd("\\[\\[[^\\]]+\\]\\]", root_dir, {
		file_type = "md",
		files_with_matches = false,
		max_count = 2000
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

-- Cache management
function M.clear_cache()
	rg_cache = {}
end

function M.get_cache_stats()
	return {
		entries = vim.tbl_count(rg_cache),
		ttl = RG_CACHE_TTL
	}
end

-- Utility functions
function M.has_ripgrep()
	local result = vim.fn.system("which " .. config.ripgrep_path .. " 2>/dev/null")
	return vim.v.shell_error == 0 and result ~= ""
end

function M.get_ripgrep_version()
	if not M.has_ripgrep() then
		return nil
	end
	
	local result = vim.fn.system(config.ripgrep_path .. " --version 2>/dev/null")
	local version = result:match("ripgrep ([%d%.]+)")
	return version
end

return M
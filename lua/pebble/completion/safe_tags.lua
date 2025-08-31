-- Safe tag completion with comprehensive error handling, resource limits, and crash protection
local M = {}

-- Safety and performance constants
local TAG_EXTRACTION_TIMEOUT = 10000  -- 10 seconds total timeout
local SINGLE_FILE_TIMEOUT = 150       -- 150ms per file
local MAX_FILES_TO_SCAN = 3000        -- Maximum files to scan
local MAX_FILE_SIZE = 5 * 1024 * 1024  -- 5MB max file size
local CACHE_TTL = 120000              -- 2 minutes cache TTL
local MAX_TAGS_IN_CACHE = 10000       -- Maximum cached tags
local BATCH_SIZE = 25                 -- Files processed per batch
local MAX_COMPLETION_ITEMS = 150      -- Maximum completion items returned
local MEMORY_THRESHOLD = 80 * 1024 * 1024  -- 80MB memory threshold
local RIPGREP_TIMEOUT = 8000          -- 8 second ripgrep timeout
local MAX_TAG_LENGTH = 100            -- Maximum individual tag length
local MAX_NESTED_DEPTH = 10           -- Maximum nested tag depth (a/b/c/d...)

-- Enhanced cache structure with comprehensive metadata
local tag_cache = {
    entries = {},           -- Array of tag entries with metadata
    frequency_map = {},     -- Tag frequency mapping
    last_update = 0,        -- Cache timestamp
    root_dir = nil,         -- Current root directory
    is_updating = false,    -- Update flag
    update_queue = {},      -- Queued update callbacks
    error_count = 0,        -- Total error count
    last_error = nil,       -- Last error message
    corruption_detected = false,  -- Cache corruption flag
    memory_usage = 0,       -- Estimated memory usage in bytes
}

-- Performance and resource tracking
local performance_metrics = {
    cache_hits = 0,
    cache_misses = 0,
    tag_extraction_time = 0,
    completion_generation_time = 0,
    error_count = 0,
    files_processed = 0,
    files_skipped = 0,
    ripgrep_calls = 0,
    ripgrep_failures = 0,
    memory_warnings = 0,
    timeout_events = 0,
    corruption_recoveries = 0,
}

-- Circuit breaker for error management
local circuit_breaker = {
    failure_count = 0,
    failure_threshold = 5,
    recovery_timeout = 30000, -- 30 seconds
    last_failure_time = 0,
    is_open = false,
}

-- Configuration with comprehensive safety defaults
local config = {
    -- Core settings
    trigger_pattern = "#",
    max_completion_items = MAX_COMPLETION_ITEMS,
    cache_ttl = CACHE_TTL,
    
    -- Tag patterns (more robust)
    inline_tag_pattern = "#([a-zA-Z0-9_][a-zA-Z0-9_/%-]*[a-zA-Z0-9_])",
    frontmatter_tag_pattern = "^%s*tags:%s*(.+)$",
    
    -- File processing limits
    max_files_scan = MAX_FILES_TO_SCAN,
    max_file_size = MAX_FILE_SIZE,
    single_file_timeout = SINGLE_FILE_TIMEOUT,
    total_timeout = TAG_EXTRACTION_TIMEOUT,
    batch_size = BATCH_SIZE,
    
    -- Feature flags
    fuzzy_matching = true,
    nested_tag_support = true,
    case_sensitive = false,
    include_frequency = true,
    async_extraction = true,
    enable_ripgrep = true,
    enable_fallback = true,
    
    -- Safety settings
    enable_memory_monitoring = true,
    enable_circuit_breaker = true,
    enable_corruption_detection = true,
    enable_performance_tracking = true,
    
    -- File patterns and exclusions
    file_patterns = { "*.md", "*.markdown", "*.txt", "*.mdx" },
    exclude_patterns = { 
        "node_modules", ".git", ".obsidian", "*.tmp", "*.log",
        "__pycache__", ".DS_Store", "Trash", "Archive"
    },
}

-- Utility functions with enhanced error handling
local function safe_require(module_name)
    local success, module = pcall(require, module_name)
    if not success then
        vim.schedule(function()
            vim.notify("Pebble: Failed to load " .. module_name .. ": " .. tostring(module), vim.log.levels.DEBUG)
        end)
        return nil
    end
    return module
end

local function get_root_dir()
    if tag_cache.root_dir then
        return tag_cache.root_dir
    end
    
    local search = safe_require("pebble.bases.search")
    if search then
        local success, root = pcall(search.get_root_dir)
        if success and root and type(root) == "string" and root ~= "" then
            tag_cache.root_dir = root
            return root
        end
    end
    
    -- Multiple fallback strategies
    local fallbacks = {
        function() return vim.fn.getcwd() end,
        function() return vim.fn.expand("%:p:h") end,
        function() return os.getenv("HOME") or "." end,
        function() return "." end,
    }
    
    for _, fallback in ipairs(fallbacks) do
        local success, result = pcall(fallback)
        if success and result and type(result) == "string" and result ~= "" then
            tag_cache.root_dir = result
            return result
        end
    end
    
    tag_cache.root_dir = "."
    return "."
end

-- Enhanced memory monitoring
local function check_memory_usage()
    if not config.enable_memory_monitoring then
        return true, 0
    end
    
    local memory_kb = collectgarbage("count")
    local memory_bytes = memory_kb * 1024
    
    -- Update cache memory usage estimate
    tag_cache.memory_usage = #tag_cache.entries * 200 -- Rough estimate per entry
    
    if memory_bytes > MEMORY_THRESHOLD then
        performance_metrics.memory_warnings = performance_metrics.memory_warnings + 1
        
        -- Progressive cleanup
        collectgarbage("collect")
        
        -- Check again after GC
        memory_kb = collectgarbage("count")
        memory_bytes = memory_kb * 1024
        
        if memory_bytes > MEMORY_THRESHOLD * 1.5 then
            -- Emergency cleanup
            if #tag_cache.entries > 1000 then
                -- Keep only top 1000 most frequent tags
                table.sort(tag_cache.entries, function(a, b)
                    return (a.frequency or 0) > (b.frequency or 0)
                end)
                
                local trimmed = {}
                for i = 1, 1000 do
                    if tag_cache.entries[i] then
                        table.insert(trimmed, tag_cache.entries[i])
                    end
                end
                tag_cache.entries = trimmed
                
                -- Rebuild frequency map
                tag_cache.frequency_map = {}
                for _, entry in ipairs(tag_cache.entries) do
                    tag_cache.frequency_map[entry.tag] = entry.frequency or 1
                end
            end
            
            collectgarbage("collect")
            memory_kb = collectgarbage("count")
            memory_bytes = memory_kb * 1024
            
            if memory_bytes > MEMORY_THRESHOLD * 1.8 then
                return false, "Critical memory usage: " .. math.floor(memory_kb) .. "KB"
            end
        end
    end
    
    return true, memory_kb
end

-- Circuit breaker management
local function update_circuit_breaker(success)
    if not config.enable_circuit_breaker then
        return
    end
    
    local now = vim.loop.now()
    
    if success then
        circuit_breaker.failure_count = 0
        circuit_breaker.is_open = false
    else
        circuit_breaker.failure_count = circuit_breaker.failure_count + 1
        circuit_breaker.last_failure_time = now
        
        if circuit_breaker.failure_count >= circuit_breaker.failure_threshold then
            circuit_breaker.is_open = true
        end
    end
end

local function is_circuit_breaker_open()
    if not config.enable_circuit_breaker then
        return false
    end
    
    if not circuit_breaker.is_open then
        return false
    end
    
    local now = vim.loop.now()
    if (now - circuit_breaker.last_failure_time) > circuit_breaker.recovery_timeout then
        circuit_breaker.is_open = false
        circuit_breaker.failure_count = 0
        return false
    end
    
    return true
end

-- Enhanced tag validation and normalization
local function normalize_tag_safe(tag)
    if not tag or type(tag) ~= "string" or tag == "" then
        return nil
    end
    
    -- Length check
    if #tag > MAX_TAG_LENGTH then
        tag = tag:sub(1, MAX_TAG_LENGTH)
    end
    
    -- Remove dangerous characters and normalize
    tag = tag:gsub('[%c%z]', ''):gsub('^[#"\' \t]+', ''):gsub('["\' \t]+$', '')
    
    -- Handle nested tags with depth limit
    if config.nested_tag_support then
        local parts = vim.split(tag, '/')
        if #parts > MAX_NESTED_DEPTH then
            parts = vim.list_slice(parts, 1, MAX_NESTED_DEPTH)
            tag = table.concat(parts, '/')
        end
        
        -- Normalize path separators and remove empty parts
        local clean_parts = {}
        for _, part in ipairs(parts) do
            part = part:gsub('^%s+', ''):gsub('%s+$', '')
            if part ~= "" then
                table.insert(clean_parts, part)
            end
        end
        
        if #clean_parts == 0 then
            return nil
        end
        
        tag = table.concat(clean_parts, '/')
    end
    
    -- Final validation
    if #tag == 0 or tag:match('^[%s/]*$') then
        return nil
    end
    
    return tag
end

-- Safe file reading with comprehensive protection
local function safe_read_file_lines(file_path, max_lines, timeout)
    max_lines = max_lines or 200
    timeout = timeout or config.single_file_timeout
    
    -- File validation
    if not file_path or type(file_path) ~= "string" or file_path == "" then
        return nil, "Invalid file path"
    end
    
    -- Check file exists and is readable
    if vim.fn.filereadable(file_path) ~= 1 then
        return nil, "File not readable"
    end
    
    -- Check file size
    local stat = vim.loop.fs_stat(file_path)
    if not stat then
        return nil, "Cannot stat file"
    end
    
    if stat.size > config.max_file_size then
        performance_metrics.files_skipped = performance_metrics.files_skipped + 1
        return nil, "File too large: " .. stat.size .. " bytes"
    end
    
    if stat.size == 0 then
        return {}, nil -- Empty file is valid
    end
    
    -- Safe file reading with timeout protection
    local lines = {}
    local start_time = vim.loop.now()
    
    local success, error_msg = pcall(function()
        local file = io.open(file_path, "r")
        if not file then
            error("Cannot open file")
        end
        
        local line_count = 0
        for line in file:lines() do
            line_count = line_count + 1
            
            -- Timeout check
            if vim.loop.now() - start_time > timeout then
                file:close()
                error("File reading timeout")
            end
            
            -- Line limit check
            if line_count > max_lines then
                break
            end
            
            -- Safety: limit line length
            if #line > 10000 then
                line = line:sub(1, 10000)
            end
            
            table.insert(lines, line)
        end
        
        file:close()
    end)
    
    if success then
        performance_metrics.files_processed = performance_metrics.files_processed + 1
        return lines, nil
    else
        performance_metrics.files_skipped = performance_metrics.files_skipped + 1
        return nil, error_msg or "File reading failed"
    end
end

-- Enhanced ripgrep tag extraction with better error handling
local function extract_tags_with_ripgrep_safe(root_dir, callback)
    if not config.enable_ripgrep then
        callback({}, {}, "Ripgrep disabled")
        return
    end
    
    local search = safe_require("pebble.bases.search")
    if not search or not search.has_ripgrep or not search.has_ripgrep() then
        callback({}, {}, "Ripgrep not available")
        return
    end
    
    performance_metrics.ripgrep_calls = performance_metrics.ripgrep_calls + 1
    
    local tags = {}
    local frequency = {}
    local completed_jobs = 0
    local total_jobs = 2
    local has_error = false
    
    local function job_completed(error_msg)
        completed_jobs = completed_jobs + 1
        if error_msg then
            has_error = true
        end
        
        if completed_jobs >= total_jobs then
            if has_error then
                performance_metrics.ripgrep_failures = performance_metrics.ripgrep_failures + 1
                update_circuit_breaker(false)
            else
                update_circuit_breaker(true)
            end
            callback(tags, frequency, has_error and "Ripgrep extraction had errors" or nil)
        end
    end
    
    -- Build ripgrep arguments with safety limits
    local base_args = {
        "rg",
        "--no-filename",
        "--no-line-number",
        "--only-matching",
        "--no-heading",
        "--max-count=1000", -- Limit matches per file
        "--max-filesize=5M", -- File size limit
    }
    
    -- Add file patterns
    for _, pattern in ipairs(config.file_patterns) do
        table.insert(base_args, "--glob")
        table.insert(base_args, pattern)
    end
    
    -- Add exclude patterns
    for _, pattern in ipairs(config.exclude_patterns) do
        table.insert(base_args, "--glob")
        table.insert(base_args, "!" .. pattern)
    end
    
    -- Job 1: Extract inline tags
    local inline_cmd = vim.deepcopy(base_args)
    table.insert(inline_cmd, config.inline_tag_pattern)
    table.insert(inline_cmd, root_dir)
    
    local inline_job = vim.fn.jobstart(inline_cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        timeout = RIPGREP_TIMEOUT,
        on_stdout = function(_, data)
            for _, line in ipairs(data or {}) do
                if line and line ~= "" then
                    local tag = normalize_tag_safe(line)
                    if tag then
                        tags[tag] = true
                        frequency[tag] = (frequency[tag] or 0) + 1
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            for _, line in ipairs(data or {}) do
                if line and line ~= "" and not line:match("^Binary file") then
                    vim.schedule(function()
                        vim.notify("Pebble ripgrep warning: " .. line, vim.log.levels.DEBUG)
                    end)
                end
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 and code ~= 1 then -- 0 = success, 1 = no matches
                job_completed("Inline tag extraction failed with code: " .. code)
            else
                job_completed(nil)
            end
        end
    })
    
    if inline_job == 0 or inline_job == -1 then
        job_completed("Failed to start inline tag extraction job")
    end
    
    -- Job 2: Extract frontmatter tags
    local frontmatter_cmd = vim.deepcopy(base_args)
    table.insert(frontmatter_cmd, "-A")
    table.insert(frontmatter_cmd, "10") -- Context lines
    table.insert(frontmatter_cmd, config.frontmatter_tag_pattern)
    table.insert(frontmatter_cmd, root_dir)
    
    local frontmatter_job = vim.fn.jobstart(frontmatter_cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        timeout = RIPGREP_TIMEOUT,
        on_stdout = function(_, data)
            local in_tags_section = false
            for _, line in ipairs(data or {}) do
                if line and line ~= "" then
                    -- Handle YAML frontmatter tags
                    local tags_match = line:match("^%s*tags:%s*(.+)$")
                    if tags_match then
                        in_tags_section = true
                        -- Handle inline array format: [tag1, tag2]
                        local array_content = tags_match:match("^%[(.+)%]$")
                        if array_content then
                            for tag_item in array_content:gmatch("([^,]+)") do
                                local tag = normalize_tag_safe(tag_item)
                                if tag then
                                    tags[tag] = true
                                    frequency[tag] = (frequency[tag] or 0) + 1
                                end
                            end
                            in_tags_section = false
                        elseif tags_match ~= "" then
                            -- Single tag
                            local tag = normalize_tag_safe(tags_match)
                            if tag then
                                tags[tag] = true
                                frequency[tag] = (frequency[tag] or 0) + 1
                            end
                            in_tags_section = false
                        end
                    elseif in_tags_section and line:match("^%s*-%s*") then
                        -- List item format: - tag
                        local list_tag = line:match("^%s*-%s*(.+)$")
                        if list_tag then
                            local tag = normalize_tag_safe(list_tag)
                            if tag then
                                tags[tag] = true
                                frequency[tag] = (frequency[tag] or 0) + 1
                            end
                        end
                    elseif in_tags_section and line:match("^%w") then
                        -- End of tags section
                        in_tags_section = false
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            for _, line in ipairs(data or {}) do
                if line and line ~= "" and not line:match("^Binary file") then
                    vim.schedule(function()
                        vim.notify("Pebble frontmatter warning: " .. line, vim.log.levels.DEBUG)
                    end)
                end
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 and code ~= 1 then
                job_completed("Frontmatter tag extraction failed with code: " .. code)
            else
                job_completed(nil)
            end
        end
    })
    
    if frontmatter_job == 0 or frontmatter_job == -1 then
        job_completed("Failed to start frontmatter tag extraction job")
    end
end

-- Safe synchronous fallback with file discovery
local function extract_tags_sync_fallback(root_dir)
    local tags = {}
    local frequency = {}
    
    -- Use safe file discovery
    local files = {}
    
    if vim.fs and vim.fs.find then
        -- Use vim.fs.find (Neovim 0.8+)
        local find_success, find_files = pcall(function()
            return vim.fs.find(function(name, path)
                -- Check file extension
                local has_valid_ext = false
                for _, pattern in ipairs(config.file_patterns) do
                    local ext = pattern:match("*%.(.+)$")
                    if ext and name:match("%." .. ext .. "$") then
                        has_valid_ext = true
                        break
                    end
                end
                
                if not has_valid_ext then
                    return false
                end
                
                -- Check exclusions
                for _, exclude in ipairs(config.exclude_patterns) do
                    if path:match(exclude) or name:match(exclude) then
                        return false
                    end
                end
                
                return true
            end, {
                path = root_dir,
                type = "file",
                limit = config.max_files_scan,
            })
        end)
        
        if find_success and find_files then
            files = find_files
        end
    end
    
    -- Fallback to glob if needed
    if #files == 0 then
        local glob_success, glob_files = pcall(function()
            local all_files = {}
            for _, pattern in ipairs(config.file_patterns) do
                local glob_pattern = root_dir .. "/**/" .. pattern
                local pattern_files = vim.fn.glob(glob_pattern, false, true)
                if pattern_files then
                    vim.list_extend(all_files, pattern_files)
                end
            end
            return all_files
        end)
        
        if glob_success and glob_files then
            files = glob_files
        end
    end
    
    -- Process files with safety measures
    local start_time = vim.loop.now()
    local processed_count = 0
    
    for _, file_path in ipairs(files) do
        -- Global timeout check
        if vim.loop.now() - start_time > config.total_timeout then
            break
        end
        
        -- Memory check every 10 files
        if processed_count % 10 == 0 then
            local memory_ok = check_memory_usage()
            if not memory_ok then
                break
            end
        end
        
        -- Process limit check
        if processed_count >= config.max_files_scan then
            break
        end
        
        processed_count = processed_count + 1
        
        -- Read file safely
        local lines, read_error = safe_read_file_lines(file_path, 100, config.single_file_timeout)
        if not lines or read_error then
            goto continue
        end
        
        -- Extract tags from file content
        local in_frontmatter = false
        local frontmatter_ended = false
        local in_tags_list = false
        
        for i, line in ipairs(lines) do
            -- Handle YAML frontmatter
            if i == 1 and line == "---" then
                in_frontmatter = true
                goto continue_line
            elseif in_frontmatter and (line == "---" or line == "...") then
                in_frontmatter = false
                frontmatter_ended = true
                in_tags_list = false
                goto continue_line
            end
            
            if in_frontmatter then
                -- Parse frontmatter tags
                local tags_line = line:match("^%s*tags:%s*(.*)$")
                if tags_line then
                    if tags_line:match("^%[.*%]$") then
                        -- Array format
                        local array_content = tags_line:match("^%[(.*)%]$")
                        if array_content then
                            for tag_item in array_content:gmatch("([^,]+)") do
                                local tag = normalize_tag_safe(tag_item)
                                if tag then
                                    tags[tag] = true
                                    frequency[tag] = (frequency[tag] or 0) + 1
                                end
                            end
                        end
                    elseif tags_line == "" then
                        -- List format starts
                        in_tags_list = true
                    else
                        -- Single tag
                        local tag = normalize_tag_safe(tags_line)
                        if tag then
                            tags[tag] = true
                            frequency[tag] = (frequency[tag] or 0) + 1
                        end
                    end
                elseif in_tags_list and line:match("^%s*-%s*") then
                    -- List item
                    local list_tag = line:match("^%s*-%s*(.+)$")
                    if list_tag then
                        local tag = normalize_tag_safe(list_tag)
                        if tag then
                            tags[tag] = true
                            frequency[tag] = (frequency[tag] or 0) + 1
                        end
                    end
                elseif in_tags_list and not line:match("^%s*-%s*") and line:match("^%w") then
                    in_tags_list = false
                end
            else
                -- Extract inline tags from content
                for tag_match in line:gmatch(config.inline_tag_pattern) do
                    local tag = normalize_tag_safe(tag_match)
                    if tag then
                        tags[tag] = true
                        frequency[tag] = (frequency[tag] or 0) + 1
                    end
                end
            end
            
            ::continue_line::
        end
        
        ::continue::
        
        -- Yield control periodically
        if processed_count % 25 == 0 then
            vim.schedule(function() end)
        end
    end
    
    return tags, frequency
end

-- Safe cache update with comprehensive error handling
local function update_cache_safe(callback)
    -- Circuit breaker check
    if is_circuit_breaker_open() then
        if callback then
            callback({}, "Circuit breaker is open")
        end
        return
    end
    
    -- Memory check
    local memory_ok, memory_info = check_memory_usage()
    if not memory_ok then
        if callback then
            callback({}, memory_info)
        end
        return
    end
    
    -- Check if cache is valid
    if tag_cache.entries and 
       #tag_cache.entries > 0 and 
       (vim.loop.now() - tag_cache.last_update) < config.cache_ttl and
       not tag_cache.is_updating and
       not tag_cache.corruption_detected then
        
        performance_metrics.cache_hits = performance_metrics.cache_hits + 1
        if callback then
            callback(tag_cache.entries, nil)
        end
        return
    end
    
    -- Handle concurrent updates
    if tag_cache.is_updating then
        table.insert(tag_cache.update_queue, callback)
        return
    end
    
    performance_metrics.cache_misses = performance_metrics.cache_misses + 1
    tag_cache.is_updating = true
    tag_cache.corruption_detected = false
    
    local start_time = vim.loop.now()
    local root_dir = get_root_dir()
    
    local function process_extraction_results(tags, frequency, error_msg)
        if error_msg then
            tag_cache.is_updating = false
            tag_cache.error_count = tag_cache.error_count + 1
            tag_cache.last_error = error_msg
            performance_metrics.error_count = performance_metrics.error_count + 1
            
            -- Execute queued callbacks with error
            for _, queued_callback in ipairs(tag_cache.update_queue) do
                if queued_callback then
                    queued_callback({}, error_msg)
                end
            end
            tag_cache.update_queue = {}
            
            if callback then
                callback({}, error_msg)
            end
            return
        end
        
        -- Convert to sortable entries array
        local entries = {}
        local total_frequency = 0
        
        for tag, _ in pairs(tags or {}) do
            local freq = frequency[tag] or 1
            total_frequency = total_frequency + freq
            
            table.insert(entries, {
                tag = tag,
                frequency = freq,
                score = freq, -- Base score from frequency
                last_seen = vim.loop.now(),
            })
        end
        
        -- Sort by frequency (descending) then alphabetically
        table.sort(entries, function(a, b)
            if a.frequency == b.frequency then
                return a.tag < b.tag
            end
            return a.frequency > b.frequency
        end)
        
        -- Apply limits for safety
        if #entries > MAX_TAGS_IN_CACHE then
            local limited = {}
            for i = 1, MAX_TAGS_IN_CACHE do
                if entries[i] then
                    table.insert(limited, entries[i])
                end
            end
            entries = limited
        end
        
        -- Update cache with corruption detection
        local old_entry_count = #tag_cache.entries
        tag_cache.entries = entries
        tag_cache.frequency_map = frequency
        tag_cache.last_update = vim.loop.now()
        tag_cache.is_updating = false
        tag_cache.error_count = 0
        tag_cache.last_error = nil
        
        -- Corruption detection
        if config.enable_corruption_detection then
            if #entries == 0 and old_entry_count > 100 then
                tag_cache.corruption_detected = true
                performance_metrics.corruption_recoveries = performance_metrics.corruption_recoveries + 1
            end
        end
        
        -- Update performance metrics
        performance_metrics.tag_extraction_time = vim.loop.now() - start_time
        
        -- Execute queued callbacks
        for _, queued_callback in ipairs(tag_cache.update_queue) do
            if queued_callback then
                queued_callback(entries, nil)
            end
        end
        tag_cache.update_queue = {}
        
        if callback then
            callback(entries, nil)
        end
    end
    
    -- Try ripgrep first if enabled and available
    if config.async_extraction and config.enable_ripgrep then
        extract_tags_with_ripgrep_safe(root_dir, process_extraction_results)
    else
        -- Use synchronous fallback
        vim.schedule(function()
            local tags, frequency = extract_tags_sync_fallback(root_dir)
            process_extraction_results(tags, frequency, nil)
        end)
    end
end

-- Enhanced fuzzy matching with performance optimization
local function calculate_tag_match_score(query, tag, frequency)
    if not query or not tag then
        return 0
    end
    
    local query_str = config.case_sensitive and query or query:lower()
    local tag_str = config.case_sensitive and tag or tag:lower()
    
    -- Base score from frequency
    local base_score = frequency or 1
    
    -- Exact match (highest score)
    if query_str == tag_str then
        return base_score * 1000
    end
    
    -- Exact prefix match (very high score)
    if tag_str:sub(1, #query_str) == query_str then
        return base_score * 500 + (50 - #tag_str)
    end
    
    -- Word boundary match (high score)
    if tag_str:match("%f[%w]" .. vim.pesc(query_str)) then
        return base_score * 250
    end
    
    -- Contains match (medium score)
    if tag_str:find(query_str, 1, true) then
        return base_score * 100
    end
    
    -- Fuzzy matching
    if config.fuzzy_matching then
        local score = 0
        local tag_idx = 1
        local matches = 0
        local consecutive_bonus = 0
        
        for i = 1, #query_str do
            local char = query_str:sub(i, i)
            local match_idx = tag_str:find(char, tag_idx, true)
            
            if match_idx then
                matches = matches + 1
                score = score + 10
                
                -- Consecutive match bonus
                if match_idx == tag_idx then
                    consecutive_bonus = consecutive_bonus + 5
                    score = score + consecutive_bonus
                else
                    consecutive_bonus = 0
                end
                
                tag_idx = match_idx + 1
            else
                return 0 -- Character not found
            end
        end
        
        -- Coverage bonus
        local coverage = matches / #tag_str
        score = score + (coverage * 50)
        
        return (base_score * score) / 100
    end
    
    return 0
end

-- Main completion function with safety measures
function M.get_tag_completions_safe(query, callback)
    -- Input validation
    if type(query) ~= "string" then
        query = ""
    end
    
    -- Safety limits on query
    if #query > 50 then
        query = query:sub(1, 50)
    end
    
    local start_time = vim.loop.now()
    
    update_cache_safe(function(entries, error_msg)
        if error_msg then
            performance_metrics.error_count = performance_metrics.error_count + 1
            if callback then
                callback({}, error_msg)
            end
            return
        end
        
        local completions = {}
        local scored_items = {}
        
        -- Process entries with scoring
        for i, entry in ipairs(entries or {}) do
            -- Processing limits
            if i > 5000 then -- Limit processing for performance
                break
            end
            
            -- Timeout check
            if vim.loop.now() - start_time > 2000 then -- 2 second timeout
                performance_metrics.timeout_events = performance_metrics.timeout_events + 1
                break
            end
            
            -- Skip if query doesn't match
            local score = calculate_tag_match_score(query, entry.tag, entry.frequency)
            if score > 0 then
                table.insert(scored_items, {
                    tag = entry.tag,
                    frequency = entry.frequency,
                    score = score,
                })
            end
        end
        
        -- Sort by score (descending)
        table.sort(scored_items, function(a, b)
            return a.score > b.score
        end)
        
        -- Build completion items
        local completion_count = 0
        for _, item in ipairs(scored_items) do
            if completion_count >= config.max_completion_items then
                break
            end
            
            local completion_item = {
                label = "#" .. item.tag,
                insertText = item.tag,
                kind = vim.lsp.protocol.CompletionItemKind.Keyword,
                detail = string.format("Used %d times", item.frequency),
                documentation = {
                    kind = "markdown",
                    value = string.format(
                        "**Tag:** `#%s`\n\nFrequency: %d\nScore: %d\n\n%s",
                        item.tag,
                        item.frequency,
                        math.floor(item.score),
                        config.nested_tag_support and item.tag:find("/") and 
                        ("Nested tag: " .. item.tag:gsub("/", " → ")) or
                        "Standard tag"
                    )
                },
                sortText = string.format("%08d", 99999999 - math.floor(item.score)),
                filterText = item.tag,
                data = {
                    type = "tag",
                    tag = item.tag,
                    frequency = item.frequency,
                    score = item.score,
                    source = "pebble_safe_tags",
                }
            }
            
            table.insert(completions, completion_item)
            completion_count = completion_count + 1
        end
        
        -- Update performance metrics
        performance_metrics.completion_generation_time = vim.loop.now() - start_time
        
        if callback then
            callback(completions, nil)
        end
    end)
end

-- Synchronous version for compatibility
function M.get_tag_completions(query)
    local completions = {}
    local completed = false
    
    M.get_tag_completions_safe(query, function(result, error_msg)
        completions = result or {}
        completed = true
    end)
    
    -- Wait with timeout
    local timeout = vim.loop.now() + 3000 -- 3 second timeout
    while not completed and vim.loop.now() < timeout do
        vim.wait(10)
    end
    
    return completions
end

-- Cache management and cleanup
function M.invalidate_cache()
    tag_cache.entries = {}
    tag_cache.frequency_map = {}
    tag_cache.last_update = 0
    tag_cache.is_updating = false
    tag_cache.update_queue = {}
    tag_cache.corruption_detected = false
    tag_cache.root_dir = nil
    
    -- Reset circuit breaker
    circuit_breaker.failure_count = 0
    circuit_breaker.is_open = false
    
    collectgarbage("collect")
end

function M.get_cache_stats()
    return {
        entries_count = #tag_cache.entries,
        last_update = tag_cache.last_update,
        cache_age = vim.loop.now() - tag_cache.last_update,
        is_updating = tag_cache.is_updating,
        error_count = tag_cache.error_count,
        last_error = tag_cache.last_error,
        corruption_detected = tag_cache.corruption_detected,
        memory_usage = tag_cache.memory_usage,
        performance = performance_metrics,
        circuit_breaker = circuit_breaker,
        root_dir = tag_cache.root_dir,
    }
end

function M.get_health_status()
    local health = {
        overall_status = "healthy",
        issues = {},
        recommendations = {},
        metrics = performance_metrics,
    }
    
    -- Check circuit breaker
    if circuit_breaker.is_open then
        health.overall_status = "degraded"
        table.insert(health.issues, "Circuit breaker is open")
        table.insert(health.recommendations, "Check error logs and consider cache refresh")
    end
    
    -- Check cache corruption
    if tag_cache.corruption_detected then
        health.overall_status = "degraded"
        table.insert(health.issues, "Cache corruption detected")
        table.insert(health.recommendations, "Refresh cache to recover")
    end
    
    -- Check memory usage
    local memory_ok = check_memory_usage()
    if not memory_ok then
        health.overall_status = "critical"
        table.insert(health.issues, "High memory usage")
        table.insert(health.recommendations, "Reduce cache size or restart Neovim")
    end
    
    -- Check error rate
    if tag_cache.error_count > 10 then
        health.overall_status = "degraded"
        table.insert(health.issues, "High error count: " .. tag_cache.error_count)
        table.insert(health.recommendations, "Check file permissions and storage")
    end
    
    return health
end

-- Configuration
function M.setup(user_config)
    config = vim.tbl_deep_extend("force", config, user_config or {})
    
    -- Validate configuration
    config.max_completion_items = math.min(config.max_completion_items, MAX_COMPLETION_ITEMS)
    config.max_files_scan = math.min(config.max_files_scan, MAX_FILES_TO_SCAN)
    config.batch_size = math.max(1, math.min(config.batch_size, 100))
    
    return true
end

return M
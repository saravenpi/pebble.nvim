-- Safe wiki link completion with comprehensive error handling and performance safeguards
local M = {}

-- Safety and performance constants
local MAX_FILES_TO_PROCESS = 2000
local FILE_PROCESSING_TIMEOUT = 8000  -- 8 seconds total timeout
local SINGLE_FILE_TIMEOUT = 200      -- 200ms per file timeout
local MAX_FILE_SIZE = 10 * 1024 * 1024  -- 10MB max file size
local CACHE_TTL = 60000              -- 1 minute cache TTL
local MAX_CACHE_ENTRIES = 5000       -- Maximum cached items
local BATCH_SIZE = 50                -- Files processed per batch
local MEMORY_THRESHOLD = 100 * 1024 * 1024  -- 100MB memory threshold

-- Cache structure with metadata
local wiki_cache = {
    notes = {},
    metadata = {},
    last_update = 0,
    root_dir = nil,
    is_updating = false,
    error_count = 0,
    last_error = nil,
}

-- Performance tracking
local performance_metrics = {
    cache_hits = 0,
    cache_misses = 0,
    file_scan_time = 0,
    completion_time = 0,
    error_count = 0,
    files_processed = 0,
    files_skipped = 0,
}

-- Configuration with sensible defaults
local config = {
    max_files = MAX_FILES_TO_PROCESS,
    file_timeout = SINGLE_FILE_TIMEOUT,
    total_timeout = FILE_PROCESSING_TIMEOUT,
    max_file_size = MAX_FILE_SIZE,
    cache_ttl = CACHE_TTL,
    max_completions = 100,
    fuzzy_matching = true,
    case_sensitive = false,
    include_aliases = true,
    include_frontmatter = true,
    async_processing = true,
    enable_performance_tracking = true,
}

-- Utility functions with error handling
local function safe_require(module_name)
    local success, module = pcall(require, module_name)
    if not success then
        vim.schedule(function()
            vim.notify("Failed to load module: " .. module_name .. " - " .. tostring(module), vim.log.levels.ERROR)
        end)
        return nil
    end
    return module
end

local function get_root_dir()
    if wiki_cache.root_dir then
        return wiki_cache.root_dir
    end
    
    local search = safe_require("pebble.bases.search")
    if search then
        local success, root = pcall(search.get_root_dir)
        if success and root then
            wiki_cache.root_dir = root
            return root
        end
    end
    
    -- Fallback to current working directory
    wiki_cache.root_dir = vim.fn.getcwd()
    return wiki_cache.root_dir
end

local function is_cache_valid()
    local now = vim.loop.now()
    return wiki_cache.notes and 
           #wiki_cache.notes > 0 and 
           (now - wiki_cache.last_update) < config.cache_ttl and
           not wiki_cache.is_updating
end

local function check_memory_usage()
    local memory_kb = collectgarbage("count")
    local memory_bytes = memory_kb * 1024
    
    if memory_bytes > MEMORY_THRESHOLD then
        -- Force garbage collection
        collectgarbage("collect")
        
        memory_kb = collectgarbage("count")
        memory_bytes = memory_kb * 1024
        
        if memory_bytes > MEMORY_THRESHOLD then
            return false, "Memory usage too high: " .. math.floor(memory_kb) .. "KB"
        end
    end
    
    return true, memory_kb
end

-- Safe file reading with size and timeout limits
local function safe_read_file(file_path, max_lines)
    max_lines = max_lines or 100
    
    -- Check file size first
    local stat = vim.loop.fs_stat(file_path)
    if not stat then
        return nil, "File stat failed"
    end
    
    if stat.size > config.max_file_size then
        performance_metrics.files_skipped = performance_metrics.files_skipped + 1
        return nil, "File too large: " .. stat.size .. " bytes"
    end
    
    -- Timeout wrapper for file reading
    local start_time = vim.loop.now()
    local lines = {}
    local error_msg = nil
    
    local success = pcall(function()
        local file = io.open(file_path, "r")
        if not file then
            error("Failed to open file")
        end
        
        local line_count = 0
        for line in file:lines() do
            line_count = line_count + 1
            table.insert(lines, line)
            
            -- Timeout check
            if vim.loop.now() - start_time > config.file_timeout then
                file:close()
                error("File reading timeout")
            end
            
            -- Line limit check
            if line_count >= max_lines then
                break
            end
        end
        
        file:close()
    end)
    
    if not success then
        performance_metrics.files_skipped = performance_metrics.files_skipped + 1
        return nil, "File reading failed"
    end
    
    performance_metrics.files_processed = performance_metrics.files_processed + 1
    return lines, nil
end

-- Safe YAML frontmatter parser with validation
local function parse_frontmatter_safe(file_path)
    local lines, error_msg = safe_read_file(file_path, 50) -- Read first 50 lines
    if not lines or error_msg then
        return nil
    end
    
    if #lines == 0 or lines[1] ~= "---" then
        return nil
    end
    
    local frontmatter = {}
    local in_frontmatter = true
    local end_found = false
    
    local success, result = pcall(function()
        for i = 2, #lines do
            local line = lines[i]
            
            if line == "---" or line == "..." then
                end_found = true
                break
            end
            
            -- Parse simple YAML key-value pairs
            local key, value = line:match("^([%w_%-]+):%s*(.*)$")
            if key then
                if value == "" then
                    -- Handle arrays (check next lines)
                    local array_items = {}
                    local j = i + 1
                    while j <= #lines and lines[j]:match("^%s*%-") do
                        local item = lines[j]:match("^%s*%-%s*(.+)$")
                        if item then
                            item = item:gsub('^["\']', ''):gsub('["\']$', '') -- Remove quotes
                            table.insert(array_items, item)
                        end
                        j = j + 1
                    end
                    if #array_items > 0 then
                        frontmatter[key] = array_items
                    end
                else
                    -- Simple value
                    value = value:gsub('^["\']', ''):gsub('["\']$', '') -- Remove quotes
                    frontmatter[key] = value
                end
            end
        end
        
        return end_found and frontmatter or nil
    end)
    
    if success then
        return result
    else
        return nil
    end
end

-- Safe note metadata extraction
local function extract_note_metadata_safe(file_path)
    local filename = vim.fn.fnamemodify(file_path, ":t:r")
    local relative_path = vim.fn.fnamemodify(file_path, ":.")
    
    -- Basic metadata
    local metadata = {
        filename = filename,
        title = filename,
        aliases = {},
        file_path = file_path,
        relative_path = relative_path,
        display_name = filename,
        size = 0,
        mtime = 0,
    }
    
    -- Get file stats
    local stat = vim.loop.fs_stat(file_path)
    if stat then
        metadata.size = stat.size
        metadata.mtime = stat.mtime.sec
    end
    
    -- Parse frontmatter if enabled
    if config.include_frontmatter then
        local frontmatter = parse_frontmatter_safe(file_path)
        if frontmatter then
            if frontmatter.title and type(frontmatter.title) == "string" then
                metadata.title = frontmatter.title
                metadata.display_name = frontmatter.title
            end
            
            if config.include_aliases then
                if frontmatter.aliases and type(frontmatter.aliases) == "table" then
                    metadata.aliases = frontmatter.aliases
                elseif frontmatter.alias and type(frontmatter.alias) == "string" then
                    metadata.aliases = {frontmatter.alias}
                end
            end
        end
    end
    
    return metadata
end

-- Safe file discovery with multiple fallback strategies
local function discover_markdown_files_safe(root_dir, callback)
    local files = {}
    local search = safe_require("pebble.bases.search")
    
    -- Strategy 1: Use pebble search module (fastest)
    if search and search.has_ripgrep then
        local ripgrep_success, ripgrep_files = pcall(function()
            if search.has_ripgrep() then
                return search.find_markdown_files_sync(root_dir)
            else
                return nil
            end
        end)
        
        if ripgrep_success and ripgrep_files and #ripgrep_files > 0 then
            files = ripgrep_files
        end
    end
    
    -- Strategy 2: vim.fs.find (Neovim 0.8+)
    if #files == 0 and vim.fs and vim.fs.find then
        local find_success, find_files = pcall(function()
            return vim.fs.find(function(name)
                return name:match("%.md$") or name:match("%.markdown$")
            end, {
                path = root_dir,
                type = "file",
                limit = config.max_files,
            })
        end)
        
        if find_success and find_files then
            files = find_files
        end
    end
    
    -- Strategy 3: vim.fn.glob fallback (most compatible)
    if #files == 0 then
        local glob_success, glob_files = pcall(function()
            local patterns = {
                root_dir .. "/**/*.md",
                root_dir .. "/**/*.markdown",
            }
            local all_files = {}
            for _, pattern in ipairs(patterns) do
                local pattern_files = vim.fn.glob(pattern, false, true)
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
    
    -- Limit and validate files
    local valid_files = {}
    for i, file_path in ipairs(files) do
        if i > config.max_files then
            break
        end
        
        if type(file_path) == "string" and 
           file_path ~= "" and 
           vim.fn.filereadable(file_path) == 1 then
            table.insert(valid_files, file_path)
        end
    end
    
    if callback then
        callback(valid_files, nil)
    else
        return valid_files
    end
end

-- Batch processing with timeout and memory management
local function process_files_in_batches(files, callback)
    local notes = {}
    local processed_count = 0
    local batch_count = 0
    local start_time = vim.loop.now()
    local errors = {}
    
    local function process_batch(start_idx)
        batch_count = batch_count + 1
        local end_idx = math.min(start_idx + BATCH_SIZE - 1, #files)
        
        -- Timeout check
        if vim.loop.now() - start_time > config.total_timeout then
            callback(notes, "Processing timeout exceeded")
            return
        end
        
        -- Memory check
        local memory_ok, memory_info = check_memory_usage()
        if not memory_ok then
            callback(notes, memory_info)
            return
        end
        
        -- Process batch
        for i = start_idx, end_idx do
            local file_path = files[i]
            local success, metadata = pcall(extract_note_metadata_safe, file_path)
            
            if success and metadata then
                table.insert(notes, metadata)
                processed_count = processed_count + 1
            else
                table.insert(errors, {
                    file = file_path,
                    error = metadata or "Unknown error"
                })
            end
            
            -- Yield control periodically
            if processed_count % 10 == 0 then
                vim.schedule(function() end)
            end
        end
        
        -- Continue with next batch or complete
        if end_idx < #files then
            vim.schedule(function()
                process_batch(end_idx + 1)
            end)
        else
            -- Processing complete
            wiki_cache.notes = notes
            wiki_cache.last_update = vim.loop.now()
            wiki_cache.is_updating = false
            wiki_cache.error_count = #errors
            
            -- Update performance metrics
            performance_metrics.file_scan_time = vim.loop.now() - start_time
            
            callback(notes, nil)
        end
    end
    
    -- Start processing
    process_batch(1)
end

-- Cache update with comprehensive safety measures
local function update_cache_safe(callback)
    if is_cache_valid() then
        performance_metrics.cache_hits = performance_metrics.cache_hits + 1
        if callback then callback(wiki_cache.notes, nil) end
        return
    end
    
    if wiki_cache.is_updating then
        -- Queue callback for when update completes
        local check_timer
        check_timer = vim.defer_fn(function()
            if not wiki_cache.is_updating then
                if callback then callback(wiki_cache.notes, nil) end
            else
                -- Retry after short delay
                check_timer()
            end
        end, 100)
        return
    end
    
    performance_metrics.cache_misses = performance_metrics.cache_misses + 1
    wiki_cache.is_updating = true
    
    local root_dir = get_root_dir()
    
    -- Discover files with error handling
    discover_markdown_files_safe(root_dir, function(files, error)
        if error or not files or #files == 0 then
            wiki_cache.is_updating = false
            wiki_cache.error_count = wiki_cache.error_count + 1
            wiki_cache.last_error = error or "No files found"
            
            if callback then
                callback({}, error or "No markdown files found")
            end
            return
        end
        
        -- Process files in batches
        process_files_in_batches(files, function(notes, batch_error)
            if batch_error then
                wiki_cache.is_updating = false
                wiki_cache.error_count = wiki_cache.error_count + 1
                wiki_cache.last_error = batch_error
                
                if callback then
                    callback(notes or {}, batch_error)
                end
                return
            end
            
            -- Success
            if callback then
                callback(notes, nil)
            end
        end)
    end)
end

-- Fuzzy matching with performance optimization
local function calculate_match_score(query, target, target_type)
    if not query or not target then
        return 0
    end
    
    local query_lower = config.case_sensitive and query or query:lower()
    local target_lower = config.case_sensitive and target or target:lower()
    
    -- Exact match gets highest score
    if query_lower == target_lower then
        return 10000
    end
    
    -- Prefix match gets very high score
    if target_lower:sub(1, #query_lower) == query_lower then
        return 5000 + (100 - #target)
    end
    
    -- Word boundary match gets high score
    local word_boundary_score = 0
    if target_lower:match("%f[%w]" .. vim.pesc(query_lower)) then
        word_boundary_score = 3000
    end
    
    -- Fuzzy matching
    local fuzzy_score = 0
    if config.fuzzy_matching then
        local target_idx = 1
        local matches = 0
        local consecutive_bonus = 0
        
        for i = 1, #query_lower do
            local char = query_lower:sub(i, i)
            local match_idx = target_lower:find(char, target_idx, true)
            
            if match_idx then
                matches = matches + 1
                fuzzy_score = fuzzy_score + 10
                
                -- Bonus for consecutive matches
                if match_idx == target_idx then
                    consecutive_bonus = consecutive_bonus + 5
                    fuzzy_score = fuzzy_score + consecutive_bonus
                else
                    consecutive_bonus = 0
                end
                
                target_idx = match_idx + 1
            else
                return 0 -- Character not found
            end
        end
        
        -- Bonus for match density
        local density = matches / #target_lower
        fuzzy_score = fuzzy_score + (density * 100)
    else
        -- Simple substring match
        if target_lower:find(query_lower, 1, true) then
            fuzzy_score = 1000
        end
    end
    
    -- Type-based scoring bonus
    local type_bonus = 0
    if target_type == "filename" then
        type_bonus = 500
    elseif target_type == "title" then
        type_bonus = 300
    elseif target_type == "alias" then
        type_bonus = 200
    end
    
    return math.max(word_boundary_score, fuzzy_score) + type_bonus
end

-- Safe completion generation
function M.get_wiki_completions_safe(query, callback)
    local start_time = vim.loop.now()
    
    -- Input validation
    if type(query) ~= "string" then
        query = ""
    end
    
    -- Limit query length for safety
    if #query > 200 then
        query = query:sub(1, 200)
    end
    
    -- Update cache and get completions
    update_cache_safe(function(notes, error)
        if error then
            performance_metrics.error_count = performance_metrics.error_count + 1
            if callback then
                callback({}, error)
            end
            return
        end
        
        local completions = {}
        local scored_items = {}
        
        -- Process each note with safety measures
        local processed = 0
        for _, note in ipairs(notes or {}) do
            processed = processed + 1
            
            -- Safety limit on processing
            if processed > MAX_CACHE_ENTRIES then
                break
            end
            
            -- Timeout check during processing
            if vim.loop.now() - start_time > 3000 then -- 3 second timeout
                break
            end
            
            -- Calculate scores for different fields
            local filename_score = calculate_match_score(query, note.filename, "filename")
            local title_score = calculate_match_score(query, note.title, "title")
            local best_alias_score = 0
            
            if config.include_aliases then
                for _, alias in ipairs(note.aliases or {}) do
                    local alias_score = calculate_match_score(query, alias, "alias")
                    best_alias_score = math.max(best_alias_score, alias_score)
                end
            end
            
            local best_score = math.max(filename_score, title_score, best_alias_score)
            
            -- Only include items with reasonable scores
            if best_score > 0 then
                -- Determine best matching text
                local match_text = note.filename
                local match_type = "filename"
                
                if title_score > filename_score and title_score >= best_alias_score then
                    match_text = note.title
                    match_type = "title"
                elseif best_alias_score > filename_score and best_alias_score > title_score then
                    -- Find the best matching alias
                    for _, alias in ipairs(note.aliases or {}) do
                        if calculate_match_score(query, alias, "alias") == best_alias_score then
                            match_text = alias
                            match_type = "alias"
                            break
                        end
                    end
                end
                
                table.insert(scored_items, {
                    score = best_score,
                    match_text = match_text,
                    match_type = match_type,
                    note = note,
                })
            end
        end
        
        -- Sort by score (highest first)
        table.sort(scored_items, function(a, b)
            return a.score > b.score
        end)
        
        -- Build final completion items
        local completion_count = 0
        for _, item in ipairs(scored_items) do
            if completion_count >= config.max_completions then
                break
            end
            
            local completion_item = {
                label = item.match_text,
                insertText = item.match_text,
                kind = 18, -- File kind
                detail = item.note.relative_path,
                documentation = {
                    kind = "markdown",
                    value = string.format(
                        "**%s** (%s)\n\nFile: `%s`\nSize: %s\nMatch: %s",
                        item.note.display_name,
                        item.match_type,
                        item.note.relative_path,
                        item.note.size and (math.floor(item.note.size / 1024) .. "KB") or "unknown",
                        item.match_type
                    )
                },
                sortText = string.format("%08d_%s", 99999999 - math.floor(item.score), item.match_text),
                score = item.score,
                data = {
                    type = "wiki_link",
                    match_type = item.match_type,
                    note_metadata = item.note,
                    source = "pebble_safe_wiki",
                }
            }
            
            table.insert(completions, completion_item)
            completion_count = completion_count + 1
        end
        
        -- Update performance metrics
        performance_metrics.completion_time = vim.loop.now() - start_time
        
        if callback then
            callback(completions, nil)
        end
    end)
end

-- Synchronous version for compatibility
function M.get_wiki_completions(query, root_dir)
    local completions = {}
    local completed = false
    
    M.get_wiki_completions_safe(query, function(result, error)
        completions = result or {}
        completed = true
    end)
    
    -- Wait for completion with timeout
    local timeout = vim.loop.now() + 5000 -- 5 second timeout
    while not completed and vim.loop.now() < timeout do
        vim.wait(10)
    end
    
    return completions
end

-- Cache management functions
function M.invalidate_cache()
    wiki_cache.notes = {}
    wiki_cache.last_update = 0
    wiki_cache.is_updating = false
    wiki_cache.root_dir = nil
end

function M.get_cache_stats()
    return {
        cache_size = #wiki_cache.notes,
        last_update = wiki_cache.last_update,
        is_updating = wiki_cache.is_updating,
        error_count = wiki_cache.error_count,
        last_error = wiki_cache.last_error,
        root_dir = wiki_cache.root_dir,
        performance = performance_metrics,
    }
end

-- Configuration
function M.setup(user_config)
    config = vim.tbl_deep_extend("force", config, user_config or {})
    return true
end

return M
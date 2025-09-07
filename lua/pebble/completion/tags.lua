local M = {}

-- Performance configurations
local TAG_CACHE_TTL = 300000  -- 5 minutes TTL
local MAX_TAG_RESULTS = 100
local RIPGREP_TIMEOUT = 1000 -- 1 second timeout for ripgrep
local MAX_FILES_SCAN = 500  -- Reduced limit for faster fallback

-- Cache structure
local tag_cache = {
    entries = {},
    frequency = {},
    last_update = 0,
    root_dir = nil,
    is_updating = false
}

-- Default configuration
local default_config = {
    -- Trigger patterns
    trigger_pattern = "#",
    
    -- Tag extraction patterns for ripgrep (improved)
    inline_tag_pattern = "#([a-zA-Z0-9_][a-zA-Z0-9_/-]*)",
    frontmatter_tag_pattern = "^\\s*tags:\\s*(.+)$",
    
    -- File patterns to search
    file_patterns = { "*.md", "*.markdown", "*.txt", "*.mdx" },
    
    -- Scoring weights
    frequency_weight = 0.7,
    recency_weight = 0.3,
    
    -- UI options
    max_completion_items = 50,
    fuzzy_matching = true,
    nested_tag_support = true,
    
    -- Performance options
    async_extraction = true,
    cache_ttl = 300000,
    max_files_scan = 500,
    
    -- Advanced options
    case_sensitive = false,
    min_tag_length = 1,
    exclude_patterns = { "node_modules", ".git", ".obsidian" }
}

local config = {}

-- Utility functions
local function get_root_dir()
    if tag_cache.root_dir then
        return tag_cache.root_dir
    end
    
    local search = require("pebble.search")
    tag_cache.root_dir = search.get_root_dir()
    return tag_cache.root_dir
end

local function is_cache_valid()
    local now = vim.loop.now()
    return (now - tag_cache.last_update) < config.cache_ttl and not tag_cache.is_updating
end

local function normalize_tag(tag)
    if not tag or tag == "" then
        return nil
    end
    
    -- Remove quotes, extra whitespace, and hash prefix if present
    tag = tag:gsub('^[#"\']', ''):gsub('["\']$', ''):gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Handle nested tags - normalize separators
    tag = tag:gsub("%s*/%s*", "/"):gsub("%s*\\%s*", "/")
    
    -- Remove trailing separators
    tag = tag:gsub("/$", "")
    
    -- Validate minimum length
    if #tag < config.min_tag_length then
        return nil
    end
    
    return tag
end

-- Check if ripgrep is available using centralized utility
local function has_ripgrep()
    local search = require("pebble.search")
    return search.has_ripgrep()
end

-- Build exclude patterns for ripgrep
local function build_exclude_patterns()
    local exclude_args = {}
    for _, pattern in ipairs(config.exclude_patterns) do
        table.insert(exclude_args, "--glob")
        table.insert(exclude_args, "!" .. pattern)
    end
    return exclude_args
end

-- Improved ripgrep-based tag extraction
local function extract_tags_with_ripgrep(root_dir, callback)
    local tags = {}
    local frequency = {}
    local completed_jobs = 0
    local total_jobs = 2
    
    local function job_completed()
        completed_jobs = completed_jobs + 1
        if completed_jobs >= total_jobs then
            callback(tags, frequency)
        end
    end
    
    -- Build file pattern arguments
    local file_pattern_args = {}
    for _, pattern in ipairs(config.file_patterns) do
        table.insert(file_pattern_args, "--glob")
        table.insert(file_pattern_args, pattern)
    end
    
    -- Build exclude pattern arguments
    local exclude_args = build_exclude_patterns()
    
    -- Extract inline tags
    local inline_cmd = {
        "rg",
        "--no-filename",
        "--no-line-number", 
        "--only-matching",
        "--no-heading",
        config.inline_tag_pattern
    }
    
    -- Add file patterns and exclude patterns
    vim.list_extend(inline_cmd, file_pattern_args)
    vim.list_extend(inline_cmd, exclude_args)
    table.insert(inline_cmd, root_dir)
    
    vim.fn.jobstart(inline_cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        timeout = RIPGREP_TIMEOUT,
        on_stdout = function(_, data)
            for _, line in ipairs(data) do
                if line and line ~= "" then
                    local tag = normalize_tag(line)
                    if tag then
                        tags[tag] = true
                        frequency[tag] = (frequency[tag] or 0) + 1
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            -- Log errors but don't fail completely
            for _, line in ipairs(data) do
                if line and line ~= "" then
                    vim.notify("Tag extraction warning: " .. line, vim.log.levels.DEBUG)
                end
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 then
                vim.notify("Inline tag extraction failed with code: " .. code, vim.log.levels.DEBUG)
            end
            job_completed()
        end
    })
    
    -- Extract frontmatter tags
    local frontmatter_cmd = {
        "rg",
        "--no-filename",
        "--only-matching",
        "--no-heading",
        "-A", "10",  -- Read up to 10 lines after tags: line
        config.frontmatter_tag_pattern
    }
    
    -- Add file patterns and exclude patterns
    vim.list_extend(frontmatter_cmd, file_pattern_args)
    vim.list_extend(frontmatter_cmd, exclude_args)
    table.insert(frontmatter_cmd, root_dir)
    
    vim.fn.jobstart(frontmatter_cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        timeout = RIPGREP_TIMEOUT,
        on_stdout = function(_, data)
            for _, line in ipairs(data) do
                if line and line ~= "" then
                    -- Extract the tag content after "tags:"
                    local tag_content = line:match("^%s*tags:%s*(.+)$")
                    if tag_content then
                        -- Handle different YAML formats
                        -- Array format: [tag1, tag2, tag3]
                        local array_match = tag_content:match("^%[(.+)%]$")
                        if array_match then
                            for tag in array_match:gmatch("([^,]+)") do
                                tag = normalize_tag(tag)
                                if tag then
                                    tags[tag] = true
                                    frequency[tag] = (frequency[tag] or 0) + 1
                                end
                            end
                        else
                            -- Single tag or string format
                            local tag = normalize_tag(tag_content)
                            if tag then
                                tags[tag] = true
                                frequency[tag] = (frequency[tag] or 0) + 1
                            end
                        end
                    else
                        -- Handle list format continuation: "  - tag"
                        local list_tag = line:match("^%s*-%s*(.+)$")
                        if list_tag then
                            local tag = normalize_tag(list_tag)
                            if tag then
                                tags[tag] = true
                                frequency[tag] = (frequency[tag] or 0) + 1
                            end
                        end
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            -- Log errors but don't fail completely
            for _, line in ipairs(data) do
                if line and line ~= "" then
                    vim.notify("Frontmatter tag extraction warning: " .. line, vim.log.levels.DEBUG)
                end
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 then
                vim.notify("Frontmatter tag extraction failed with code: " .. code, vim.log.levels.DEBUG)
            end
            job_completed()
        end
    })
end

-- Improved synchronous fallback for tag extraction
local function extract_tags_sync(root_dir)
    local tags = {}
    local frequency = {}
    
    -- Use vim.fs.find for better cross-platform compatibility
    local files = vim.fs.find(function(name, path)
        -- Check file extension
        local ext_match = false
        for _, pattern in ipairs(config.file_patterns) do
            local ext = pattern:match("*%.(.+)$")
            if ext and name:match("%." .. ext .. "$") then
                ext_match = true
                break
            end
        end
        
        if not ext_match then
            return false
        end
        
        -- Check exclude patterns
        for _, exclude_pattern in ipairs(config.exclude_patterns) do
            if path:match(exclude_pattern) then
                return false
            end
        end
        
        return true
    end, {
        path = root_dir,
        type = "file",
        limit = config.max_files_scan
    })
    
    if not files then
        return tags, frequency
    end
    
    local processed = 0
    for _, file_path in ipairs(files) do
        if vim.fn.filereadable(file_path) == 1 then
            local lines = vim.fn.readfile(file_path, "", 100) -- Read first 100 lines only
            
            local in_frontmatter = false
            local frontmatter_ended = false
            local in_tags_list = false
            
            for i, line in ipairs(lines) do
                -- Handle YAML frontmatter
                if i == 1 and line == "---" then
                    in_frontmatter = true
                    goto continue
                elseif in_frontmatter and (line == "---" or line == "...") then
                    frontmatter_ended = true
                    in_frontmatter = false
                    in_tags_list = false
                    goto continue
                end
                
                if in_frontmatter then
                    -- Handle tags in frontmatter
                    local tags_line = line:match("^%s*tags:%s*(.*)$")
                    if tags_line then
                        if tags_line:match("^%[.*%]$") then
                            -- Array format: [tag1, tag2, tag3]
                            local array_content = tags_line:match("^%[(.*)%]$")
                            if array_content then
                                for tag in array_content:gmatch("([^,]+)") do
                                    tag = normalize_tag(tag)
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
                            local tag = normalize_tag(tags_line)
                            if tag then
                                tags[tag] = true
                                frequency[tag] = (frequency[tag] or 0) + 1
                            end
                        end
                    elseif in_tags_list and line:match("^%s*-%s*") then
                        -- List item
                        local list_tag = line:match("^%s*-%s*(.+)$")
                        if list_tag then
                            local tag = normalize_tag(list_tag)
                            if tag then
                                tags[tag] = true
                                frequency[tag] = (frequency[tag] or 0) + 1
                            end
                        end
                    elseif in_tags_list and not line:match("^%s*-%s*") and line:match("^%w") then
                        -- End of tags list
                        in_tags_list = false
                    end
                else
                    -- Extract inline tags from content
                    for tag in line:gmatch(config.inline_tag_pattern) do
                        tag = normalize_tag(tag)
                        if tag then
                            tags[tag] = true
                            frequency[tag] = (frequency[tag] or 0) + 1
                        end
                    end
                end
                
                ::continue::
            end
            
            processed = processed + 1
            -- Yield control periodically
            if processed % 50 == 0 then
                vim.schedule(function() end)
            end
        end
    end
    
    return tags, frequency
end

-- Cache management with improved performance
local function update_tag_cache(callback)
    if is_cache_valid() then
        if callback then callback() end
        return
    end
    
    if tag_cache.is_updating then
        -- Queue the callback to avoid duplicate work
        if callback then
            vim.defer_fn(function()
                if is_cache_valid() then
                    callback()
                else
                    -- Retry after a short delay
                    update_tag_cache(callback)
                end
            end, 100)
        end
        return
    end
    
    tag_cache.is_updating = true
    local root_dir = get_root_dir()
    
    local function process_results(tags, frequency)
        -- Convert to sortable array
        local tag_list = {}
        for tag, _ in pairs(tags) do
            table.insert(tag_list, {
                tag = tag,
                frequency = frequency[tag] or 1,
                score = frequency[tag] or 1
            })
        end
        
        -- Sort by frequency (descending) then alphabetically
        table.sort(tag_list, function(a, b)
            if a.frequency == b.frequency then
                return a.tag < b.tag
            end
            return a.frequency > b.frequency
        end)
        
        -- Limit results for performance
        if #tag_list > MAX_TAG_RESULTS then
            local limited = {}
            for i = 1, MAX_TAG_RESULTS do
                limited[i] = tag_list[i]
            end
            tag_list = limited
        end
        
        tag_cache.entries = tag_list
        tag_cache.frequency = frequency
        tag_cache.last_update = vim.loop.now()
        tag_cache.is_updating = false
        
        if callback then callback() end
    end
    
    if config.async_extraction and has_ripgrep() then
        extract_tags_with_ripgrep(root_dir, process_results)
    else
        -- Use synchronous extraction in a separate coroutine for better performance
        vim.schedule(function()
            local tags, frequency = extract_tags_sync(root_dir)
            process_results(tags, frequency)
        end)
    end
end

-- Improved fuzzy matching implementation
local function fuzzy_match(tag, pattern)
    if not pattern or pattern == "" then
        return true
    end
    
    if not config.fuzzy_matching then
        if config.case_sensitive then
            return tag:find(pattern, 1, true) ~= nil
        else
            return tag:lower():find(pattern:lower(), 1, true) ~= nil
        end
    end
    
    -- Case handling
    local search_tag = config.case_sensitive and tag or tag:lower()
    local search_pattern = config.case_sensitive and pattern or pattern:lower()
    
    local tag_idx = 1
    for i = 1, #search_pattern do
        local char = search_pattern:sub(i, i)
        local found_idx = search_tag:find(char, tag_idx, true)
        if not found_idx then
            return false
        end
        tag_idx = found_idx + 1
    end
    return true
end

-- Calculate fuzzy match score with improved algorithm
local function calculate_match_score(tag, pattern)
    local base_score = tag_cache.frequency[tag] or 1
    
    if not pattern or pattern == "" then
        return base_score
    end
    
    -- Case handling for scoring
    local search_tag = config.case_sensitive and tag or tag:lower()
    local search_pattern = config.case_sensitive and pattern or pattern:lower()
    
    -- Exact match gets highest score
    if search_tag == search_pattern then
        return base_score * 100
    end
    
    -- Exact prefix match gets very high score
    if search_tag:sub(1, #search_pattern) == search_pattern then
        return base_score * 50
    end
    
    -- Word boundary match gets high score
    if search_tag:match("^" .. vim.pesc(search_pattern) .. "%W") or search_tag:match("%W" .. vim.pesc(search_pattern) .. "%W") then
        return base_score * 25
    end
    
    -- Contains pattern gets medium score
    if search_tag:find(search_pattern, 1, true) then
        return base_score * 10
    end
    
    -- Fuzzy match gets base score modified by match quality
    local score_multiplier = 1
    local consecutive_matches = 0
    local tag_idx = 1
    
    for i = 1, #search_pattern do
        local char = search_pattern:sub(i, i)
        local found_idx = search_tag:find(char, tag_idx, true)
        if found_idx then
            if found_idx == tag_idx then
                consecutive_matches = consecutive_matches + 1
                score_multiplier = score_multiplier + 0.5
            end
            tag_idx = found_idx + 1
        end
    end
    
    return base_score * score_multiplier
end

-- Get completion items with improved performance and sorting
local function get_completion_items(pattern)
    if not is_cache_valid() then
        return {}
    end
    
    local items = {}
    local scored_items = {}
    
    for _, entry in ipairs(tag_cache.entries) do
        local tag = entry.tag
        
        -- Skip if pattern doesn't match
        if pattern and pattern ~= "" and not fuzzy_match(tag, pattern) then
            goto continue
        end
        
        -- Calculate match score
        local score = calculate_match_score(tag, pattern)
        
        table.insert(scored_items, {
            tag = tag,
            frequency = entry.frequency,
            score = score
        })
        
        ::continue::
    end
    
    -- Sort by score (descending)
    table.sort(scored_items, function(a, b)
        return a.score > b.score
    end)
    
    -- Build final completion items
    local added_count = 0
    for _, item in ipairs(scored_items) do
        if added_count >= config.max_completion_items then
            break
        end
        
        local completion_item = {
            label = "#" .. item.tag,
            kind = vim.lsp.protocol.CompletionItemKind.Keyword,
            insertText = item.tag,
            detail = string.format("Used %d times", item.frequency),
            sortText = string.format("%08d", 99999999 - math.floor(item.score)),
            filterText = item.tag,
            word = item.tag, -- For omnifunc compatibility
        }
        
        -- Add documentation for nested tags
        if config.nested_tag_support and item.tag:find("/") then
            local parts = vim.split(item.tag, "/")
            completion_item.documentation = {
                kind = "markdown",
                value = "**Nested tag:** " .. table.concat(parts, " → ") .. "\n\n**Frequency:** " .. item.frequency
            }
        else
            completion_item.documentation = {
                kind = "markdown", 
                value = "**Tag:** #" .. item.tag .. "\n\n**Frequency:** " .. item.frequency
            }
        end
        
        table.insert(items, completion_item)
        added_count = added_count + 1
    end
    
    return items
end

-- Improved completion source for nvim-cmp
function M.get_completion_source()
    return {
        name = "pebble_tags",
        
        -- Check if completion should trigger
        is_available = function()
            local buf = vim.api.nvim_get_current_buf()
            local filetype = vim.bo[buf].filetype
            return filetype == "markdown" or filetype == "md" or filetype == "mdx"
        end,
        
        -- Get trigger characters
        get_trigger_characters = function()
            return { config.trigger_pattern }
        end,
        
        -- Complete function
        complete = function(self, params, callback)
            -- Check if we're at a # trigger
            local line = params.context.cursor_line
            local col = params.context.cursor.character
            
            -- Look for # before cursor
            local before_cursor = line:sub(1, col)
            local hash_match = before_cursor:match(".*#([a-zA-Z0-9_/-]*)$")
            
            if not hash_match then
                callback({ items = {}, isIncomplete = false })
                return
            end
            
            -- Update cache and get items
            update_tag_cache(function()
                local items = get_completion_items(hash_match)
                callback({
                    items = items,
                    isIncomplete = #items >= config.max_completion_items
                })
            end)
        end,
        
        -- Resolve additional info
        resolve = function(self, completion_item, callback)
            callback(completion_item)
        end,
    }
end

-- Improved blink.cmp compatibility
function M.get_blink_source()
    local source = {}
    
    -- Source configuration
    source.name = "pebble_tags"
    source.priority = 1000
    
    -- Check if available
    function source.enabled(ctx)
        if not ctx or not ctx.filetype then
            local buf = vim.api.nvim_get_current_buf()
            local filetype = vim.bo[buf].filetype
            return filetype == "markdown" or filetype == "md" or filetype == "mdx"
        end
        return ctx.filetype == "markdown" or ctx.filetype == "md" or ctx.filetype == "mdx"
    end
    
    -- Get trigger characters
    function source.get_trigger_characters()
        return { "#" }
    end
    
    -- Should show completion on trigger character
    function source.should_show_completion_on_trigger_character(ctx, trigger_char)
        if trigger_char ~= "#" then
            return false
        end
        
        -- Only trigger if we're not already in a tag or if this could be a new tag
        local line_before_cursor = ctx.line and ctx.line:sub(1, ctx.cursor.col - 1) or ""
        return true  -- Let the get_completions function handle the detailed logic
    end
    
    -- Get completions (main completion function)
    function source.get_completions(ctx, callback)
        if not ctx.line then
            callback({ items = {}, is_incomplete = false })
            return
        end
        
        -- Check for # trigger
        local line_before_cursor = ctx.line:sub(1, ctx.cursor.col - 1)
        local hash_match = line_before_cursor:match(".*#([a-zA-Z0-9_/-]*)$")
        
        if not hash_match then
            callback({ items = {}, is_incomplete = false })
            return
        end
        
        -- Update cache and get completions asynchronously
        update_tag_cache(function()
            local items = get_completion_items(hash_match)
            
            -- Convert items for blink.cmp format
            local blink_items = {}
            for _, item in ipairs(items) do
                table.insert(blink_items, {
                    label = item.label,
                    kind = item.kind,
                    detail = item.detail,
                    documentation = item.documentation,
                    insertText = item.insertText,
                    sortText = item.sortText,
                    filterText = item.filterText,
                    score = item.score or 1000,
                })
            end
            
            callback({ 
                items = blink_items, 
                is_incomplete = #blink_items >= config.max_completion_items 
            })
        end)
    end
    
    -- Resolve completion item (optional)
    function source.resolve(item, callback)
        callback(item)
    end
    
    return source
end

-- Force cache refresh
function M.refresh_cache()
    tag_cache.last_update = 0
    tag_cache.is_updating = false
    update_tag_cache()
end

-- Get cache statistics
function M.get_cache_stats()
    return {
        entries_count = #tag_cache.entries,
        last_update = tag_cache.last_update,
        cache_age = vim.loop.now() - tag_cache.last_update,
        is_valid = is_cache_valid(),
        is_updating = tag_cache.is_updating,
        root_dir = tag_cache.root_dir,
        has_ripgrep = has_ripgrep(),
        config = config
    }
end

-- Manual trigger for completion
function M.trigger_completion()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    
    -- Insert # if not present
    if col == 0 or line:sub(col, col) ~= "#" then
        vim.api.nvim_put({"#"}, "c", true, true)
        col = col + 1
    end
    
    -- Trigger completion manually
    vim.schedule(function()
        -- Try different completion triggers
        if vim.fn.exists("*cmp#complete") == 1 then
            vim.fn["cmp#complete"]()
        else
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-u>", true, false, true), "n", false)
        end
    end)
end

-- Initialize tag completion
function M.setup(user_config)
    config = vim.tbl_deep_extend("force", default_config, user_config or {})
    
    -- Pre-warm cache asynchronously with immediate warmup
    vim.schedule(function()
        update_tag_cache()
    end)
    
    -- Additional warmup after a short delay to ensure better initial performance
    vim.defer_fn(function()
        if not is_cache_valid() then
            update_tag_cache()
        end
    end, 100)
    
    -- Auto-refresh cache on file changes with debouncing
    local refresh_timer = nil
    vim.api.nvim_create_autocmd({"BufWritePost", "BufNewFile", "BufDelete"}, {
        pattern = vim.list_extend({}, config.file_patterns),
        callback = function()
            -- Debounce refresh to avoid excessive cache updates
            if refresh_timer then
                refresh_timer:stop()
            end
            refresh_timer = vim.defer_fn(function()
                M.refresh_cache()
                refresh_timer = nil
            end, 500) -- 500ms delay for snappier response
        end,
    })
    
    -- Invalidate cache when changing directories
    vim.api.nvim_create_autocmd("DirChanged", {
        callback = function()
            tag_cache.root_dir = nil
            M.refresh_cache()
        end,
    })
end

return M
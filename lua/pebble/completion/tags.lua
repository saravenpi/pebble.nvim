local M = {}

-- Performance configurations
local TAG_CACHE_TTL = 60000  -- 1 minute TTL
local MAX_TAG_RESULTS = 100
local RIPGREP_TIMEOUT = 2000 -- 2 second timeout for ripgrep

-- Cache structure
local tag_cache = {
    entries = {},
    frequency = {},
    last_update = 0,
    root_dir = nil
}

-- Default configuration
local default_config = {
    -- Trigger patterns
    trigger_pattern = "#",
    
    -- Tag extraction patterns for ripgrep
    inline_tag_pattern = "#([a-zA-Z0-9_/-]+)",
    frontmatter_tag_pattern = "tags:\\s*\\[([^\\]]+)\\]|tags:\\s*-\\s*([^\\n]+)",
    
    -- File patterns to search
    file_patterns = { "*.md", "*.markdown", "*.txt" },
    
    -- Scoring weights
    frequency_weight = 0.7,
    recency_weight = 0.3,
    
    -- UI options
    max_completion_items = 50,
    fuzzy_matching = true,
    nested_tag_support = true,
    
    -- Performance options
    async_extraction = true,
    cache_ttl = 60000,
    max_files_scan = 1000,
}

local config = {}

-- Utility functions
local function get_root_dir()
    if tag_cache.root_dir then
        return tag_cache.root_dir
    end
    
    local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
    if vim.v.shell_error == 0 and git_root ~= "" then
        tag_cache.root_dir = git_root
    else
        tag_cache.root_dir = vim.fn.getcwd()
    end
    
    return tag_cache.root_dir
end

local function is_cache_valid()
    local now = vim.loop.now()
    return (now - tag_cache.last_update) < config.cache_ttl
end

local function normalize_tag(tag)
    -- Remove quotes and extra whitespace
    tag = tag:gsub('^["\']', ''):gsub('["\']$', ''):gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Handle nested tags - normalize separators
    tag = tag:gsub("%s*/%s*", "/"):gsub("%s*\\%s*", "/")
    
    return tag
end

-- Ripgrep-based tag extraction
local function extract_tags_with_ripgrep(root_dir, callback)
    local tags = {}
    local frequency = {}
    
    -- Build ripgrep command for inline tags
    local inline_cmd = string.format(
        "rg --no-filename --no-line-number --only-matching '%s' %s 2>/dev/null",
        config.inline_tag_pattern,
        table.concat(vim.tbl_map(function(pattern) return "'" .. root_dir .. "/" .. pattern .. "'" end, config.file_patterns), " ")
    )
    
    -- Build ripgrep command for frontmatter tags
    local frontmatter_cmd = string.format(
        "rg --no-filename --only-matching '%s' %s 2>/dev/null",
        config.frontmatter_tag_pattern,
        table.concat(vim.tbl_map(function(pattern) return "'" .. root_dir .. "/" .. pattern .. "'" end, config.file_patterns), " ")
    )
    
    local function process_inline_tags()
        vim.fn.jobstart(inline_cmd, {
            stdout_buffered = true,
            on_stdout = function(_, data)
                for _, line in ipairs(data) do
                    if line and line ~= "" then
                        -- Extract tag from match (remove the # prefix)
                        local tag = line:match("#([a-zA-Z0-9_/-]+)")
                        if tag then
                            tag = normalize_tag(tag)
                            if tag ~= "" then
                                tags[tag] = true
                                frequency[tag] = (frequency[tag] or 0) + 1
                            end
                        end
                    end
                end
            end,
            on_exit = function(_, code)
                if code == 0 then
                    process_frontmatter_tags()
                else
                    -- Fallback to simple grep if ripgrep fails
                    callback(tags, frequency)
                end
            end
        })
    end
    
    local function process_frontmatter_tags()
        vim.fn.jobstart(frontmatter_cmd, {
            stdout_buffered = true,
            on_stdout = function(_, data)
                for _, line in ipairs(data) do
                    if line and line ~= "" then
                        -- Parse frontmatter tags
                        -- Handle array format: tags: [tag1, tag2, tag3]
                        local array_match = line:match("tags:%s*%[([^%]]+)%]")
                        if array_match then
                            for tag in array_match:gmatch("([^,]+)") do
                                tag = normalize_tag(tag)
                                if tag ~= "" then
                                    tags[tag] = true
                                    frequency[tag] = (frequency[tag] or 0) + 1
                                end
                            end
                        else
                            -- Handle list format: tags: - tag1
                            local list_match = line:match("tags:%s*-%s*([^%s]+)")
                            if list_match then
                                local tag = normalize_tag(list_match)
                                if tag ~= "" then
                                    tags[tag] = true
                                    frequency[tag] = (frequency[tag] or 0) + 1
                                end
                            end
                        end
                    end
                end
            end,
            on_exit = function(_, code)
                callback(tags, frequency)
            end
        })
    end
    
    process_inline_tags()
end

-- Synchronous fallback for tag extraction
local function extract_tags_sync(root_dir)
    local tags = {}
    local frequency = {}
    
    -- Simple find + grep fallback
    local find_cmd = string.format("find '%s' -name '*.md' -o -name '*.markdown' -o -name '*.txt' | head -n %d", 
                                   root_dir, config.max_files_scan)
    local files_result = vim.fn.system(find_cmd)
    
    if vim.v.shell_error ~= 0 then
        return tags, frequency
    end
    
    for file_path in files_result:gmatch("[^\n]+") do
        if vim.fn.filereadable(file_path) == 1 then
            local lines = vim.fn.readfile(file_path, "", 200) -- Read first 200 lines only for performance
            
            for _, line in ipairs(lines) do
                -- Extract inline tags
                for tag in line:gmatch("#([a-zA-Z0-9_/-]+)") do
                    tag = normalize_tag(tag)
                    if tag ~= "" then
                        tags[tag] = true
                        frequency[tag] = (frequency[tag] or 0) + 1
                    end
                end
                
                -- Extract frontmatter tags
                local array_match = line:match("tags:%s*%[([^%]]+)%]")
                if array_match then
                    for tag in array_match:gmatch("([^,]+)") do
                        tag = normalize_tag(tag)
                        if tag ~= "" then
                            tags[tag] = true
                            frequency[tag] = (frequency[tag] or 0) + 1
                        end
                    end
                end
                
                local list_match = line:match("tags:%s*-%s*([^%s]+)")
                if list_match then
                    local tag = normalize_tag(list_match)
                    if tag ~= "" then
                        tags[tag] = true
                        frequency[tag] = (frequency[tag] or 0) + 1
                    end
                end
            end
        end
    end
    
    return tags, frequency
end

-- Cache management
local function update_tag_cache(callback)
    if is_cache_valid() then
        if callback then callback() end
        return
    end
    
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
        
        -- Sort by frequency (descending)
        table.sort(tag_list, function(a, b) return a.frequency > b.frequency end)
        
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
        
        if callback then callback() end
    end
    
    if config.async_extraction then
        extract_tags_with_ripgrep(root_dir, process_results)
    else
        local tags, frequency = extract_tags_sync(root_dir)
        process_results(tags, frequency)
    end
end

-- Fuzzy matching implementation
local function fuzzy_match(tag, pattern)
    if not config.fuzzy_matching then
        return tag:lower():find(pattern:lower(), 1, true) ~= nil
    end
    
    pattern = pattern:lower()
    tag = tag:lower()
    
    local tag_idx = 1
    for i = 1, #pattern do
        local char = pattern:sub(i, i)
        local found_idx = tag:find(char, tag_idx, true)
        if not found_idx then
            return false
        end
        tag_idx = found_idx + 1
    end
    return true
end

-- Calculate fuzzy match score
local function calculate_match_score(tag, pattern)
    local base_score = tag_cache.frequency[tag] or 1
    
    if not pattern or pattern == "" then
        return base_score
    end
    
    -- Exact prefix match gets highest score
    if tag:lower():sub(1, #pattern) == pattern:lower() then
        return base_score * 10
    end
    
    -- Contains pattern gets medium score
    if tag:lower():find(pattern:lower(), 1, true) then
        return base_score * 3
    end
    
    -- Fuzzy match gets base score
    return base_score
end

-- Get completion items
local function get_completion_items(pattern)
    if not is_cache_valid() then
        return {}
    end
    
    local items = {}
    local added_count = 0
    
    for _, entry in ipairs(tag_cache.entries) do
        if added_count >= config.max_completion_items then
            break
        end
        
        local tag = entry.tag
        
        -- Skip if pattern doesn't match
        if pattern and pattern ~= "" and not fuzzy_match(tag, pattern) then
            goto continue
        end
        
        -- Calculate match score
        local score = calculate_match_score(tag, pattern)
        
        -- Build completion item
        local item = {
            label = "#" .. tag,
            kind = vim.lsp.protocol.CompletionItemKind.Keyword,
            insertText = tag,
            detail = string.format("frequency: %d", entry.frequency),
            sortText = string.format("%08d", 99999999 - score), -- Reverse score for sorting
            filterText = tag,
            word = tag, -- For omnifunc compatibility
        }
        
        -- Add documentation for nested tags
        if config.nested_tag_support and tag:find("/") then
            local parts = vim.split(tag, "/")
            item.documentation = {
                kind = "markdown",
                value = "**Nested tag:** " .. table.concat(parts, " → ")
            }
        end
        
        table.insert(items, item)
        added_count = added_count + 1
        
        ::continue::
    end
    
    return items
end

-- Completion source for nvim-cmp
function M.get_completion_source()
    return {
        name = "pebble_tags",
        
        -- Check if completion should trigger
        is_available = function()
            local buf = vim.api.nvim_get_current_buf()
            local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
            return filetype == "markdown" or filetype == "md"
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
                -- Adjust insertText to not include # since it's already typed
                for _, item in ipairs(items) do
                    item.insertText = item.insertText or item.label:sub(2) -- Remove # prefix
                end
                callback({
                    items = items,
                    isIncomplete = #items >= config.max_completion_items
                })
            end)
        end,
        
        -- Resolve additional info (optional)
        resolve = function(self, completion_item, callback)
            callback(completion_item)
        end,
    }
end

-- Blink.cmp compatibility
function M.get_blink_source()
    return {
        name = "pebble_tags",
        
        -- Module methods for blink.cmp
        get_completions = function(self, ctx, callback)
            if not ctx.line then
                callback({ items = {} })
                return
            end
            
            -- Check for # trigger
            local line_before_cursor = ctx.line:sub(1, ctx.cursor.col - 1)
            local hash_match = line_before_cursor:match(".*#([a-zA-Z0-9_/-]*)$")
            
            if not hash_match then
                callback({ items = {} })
                return
            end
            
            -- Update cache and get completions
            update_tag_cache(function()
                local items = get_completion_items(hash_match)
                -- Adjust insertText for blink.cmp
                for _, item in ipairs(items) do
                    item.insertText = item.insertText or item.label:sub(2) -- Remove # prefix
                end
                callback({ items = items })
            end)
        end,
        
        get_trigger_characters = function()
            return { "#" }
        end,
    }
end

-- Force cache refresh
function M.refresh_cache()
    tag_cache.last_update = 0
    update_tag_cache()
end

-- Get cache statistics
function M.get_cache_stats()
    return {
        entries_count = #tag_cache.entries,
        last_update = tag_cache.last_update,
        cache_age = vim.loop.now() - tag_cache.last_update,
        is_valid = is_cache_valid(),
        root_dir = tag_cache.root_dir,
    }
end

-- Initialize tag completion
function M.setup(user_config)
    config = vim.tbl_deep_extend("force", default_config, user_config or {})
    
    -- Pre-warm cache
    update_tag_cache()
    
    -- Auto-refresh cache on file changes
    vim.api.nvim_create_autocmd({"BufWritePost", "BufNewFile"}, {
        pattern = {"*.md", "*.markdown", "*.txt"},
        callback = function()
            -- Delay refresh to avoid performance issues during active editing
            vim.defer_fn(function()
                M.refresh_cache()
            end, 1000)
        end,
    })
end

-- Manual trigger for completion (for testing)
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
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-u>", true, false, true), "n", false)
    end)
end

return M
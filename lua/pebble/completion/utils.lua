-- Utility functions for completion system
local M = {}

-- Import the search module for ripgrep functionality
local search = require("pebble.bases.search")

-- Cache management
local cache = {}
local cache_ttl = 30000 -- 30 seconds default
local cache_max_size = 2000

-- Set cache configuration
function M.set_cache_config(ttl, max_size)
    cache_ttl = ttl or cache_ttl
    cache_max_size = max_size or cache_max_size
end

-- Invalidate the entire cache
function M.invalidate_cache()
    cache = {}
end

-- Get cache statistics
function M.get_cache_stats()
    local size = 0
    for _ in pairs(cache) do
        size = size + 1
    end
    return {
        size = size,
        max_size = cache_max_size,
        ttl = cache_ttl
    }
end

-- Get overall statistics
function M.get_stats()
    return {
        cache = M.get_cache_stats(),
        enabled = true
    }
end

-- Context detection functions
function M.is_wiki_link_context()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    
    -- Check for [[ pattern before cursor
    local before_cursor = line:sub(1, col)
    local wiki_start = before_cursor:match("%[%[([^%]]*)")
    
    if wiki_start then
        return true, wiki_start
    end
    
    return false, nil
end

function M.is_markdown_link_context()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    
    -- Check for ]( pattern before cursor
    local before_cursor = line:sub(1, col)
    local link_start = before_cursor:match("%]%(([^%)]*)")
    
    if link_start then
        return true, link_start
    end
    
    return false, nil
end

-- Tag context detection
function M.is_tag_context()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    
    -- Check for # pattern before cursor
    local before_cursor = line:sub(1, col)
    local tag_start = before_cursor:match("#([%w_/-]*)")
    
    if tag_start ~= nil then  -- tag_start can be an empty string, which is valid
        return true, tag_start
    end
    
    return false, nil
end

-- Get root directory for searching
function M.get_root_dir()
    return search.get_root_dir()
end

-- Get wiki completions using ripgrep
function M.get_wiki_completions(query, root_dir)
    local cache_key = "wiki_" .. (root_dir or "") .. "_" .. (query or "")
    
    -- Check cache first
    local cached = cache[cache_key]
    if cached and (vim.loop.now() - cached.timestamp) < cache_ttl then
        return cached.data
    end
    
    -- Find markdown files using the search module
    local markdown_files = search.find_markdown_files_sync(root_dir)
    local completions = {}
    
    if not markdown_files or #markdown_files == 0 then
        return {
            {
                label = "No markdown files found",
                kind = vim.lsp.protocol.CompletionItemKind.Text,
                detail = "Create .md files to see wiki link completions",
                insertText = "new-note"
            }
        }
    end
    
    -- Process each file to create completion items
    for _, file_path in ipairs(markdown_files) do
        local filename = vim.fn.fnamemodify(file_path, ":t:r") -- Get filename without extension
        local relative_path = vim.fn.fnamemodify(file_path, ":~:.")
        
        -- Filter based on query if provided
        if not query or query == "" or filename:lower():match(query:lower()) then
            table.insert(completions, {
                label = filename,
                kind = vim.lsp.protocol.CompletionItemKind.File,
                detail = relative_path,
                insertText = filename,
                documentation = "Wiki link to " .. relative_path,
                sortText = string.format("%04d_%s", #filename, filename) -- Sort by length then name
            })
        end
    end
    
    -- Sort completions by relevance (shorter names first, then alphabetical)
    table.sort(completions, function(a, b)
        local a_len = #a.label
        local b_len = #b.label
        if a_len == b_len then
            return a.label < b.label
        end
        return a_len < b_len
    end)
    
    -- Limit results to prevent UI lag
    if #completions > 50 then
        local limited = {}
        for i = 1, 50 do
            table.insert(limited, completions[i])
        end
        completions = limited
    end
    
    -- Cache the results
    cache[cache_key] = {
        data = completions,
        timestamp = vim.loop.now()
    }
    
    return completions
end

-- Get markdown link completions using ripgrep
function M.get_markdown_link_completions(query, root_dir)
    local cache_key = "markdown_" .. (root_dir or "") .. "_" .. (query or "")
    
    -- Check cache first
    local cached = cache[cache_key]
    if cached and (vim.loop.now() - cached.timestamp) < cache_ttl then
        return cached.data
    end
    
    -- Find markdown files using the search module
    local markdown_files = search.find_markdown_files_sync(root_dir)
    local completions = {}
    
    if not markdown_files or #markdown_files == 0 then
        return {
            {
                label = "No markdown files found",
                kind = vim.lsp.protocol.CompletionItemKind.Text,
                detail = "Create .md files to see link completions",
                insertText = "./new-note.md"
            }
        }
    end
    
    -- Get current buffer directory for relative paths
    local current_file = vim.fn.expand("%:p")
    local current_dir = vim.fn.fnamemodify(current_file, ":h")
    
    -- Process each file to create completion items
    for _, file_path in ipairs(markdown_files) do
        local filename = vim.fn.fnamemodify(file_path, ":t")
        local relative_path = vim.fn.fnamemodify(file_path, ":~:.")
        
        -- Create relative path from current file
        local relative_from_current = vim.fn.fnamemodify(file_path, ":.")
        if current_dir and current_dir ~= "" then
            -- Try to make path relative to current file's directory
            local current_relative = vim.fn.substitute(file_path, vim.fn.escape(current_dir, '[]'), '.', '')
            if current_relative:sub(1, 1) ~= '/' then
                relative_from_current = current_relative
            end
        end
        
        -- Filter based on query if provided
        if not query or query == "" or filename:lower():match(query:lower()) or relative_path:lower():match(query:lower()) then
            table.insert(completions, {
                label = relative_from_current,
                kind = vim.lsp.protocol.CompletionItemKind.File,
                detail = relative_path,
                insertText = relative_from_current,
                documentation = "Link to " .. relative_path,
                sortText = string.format("%04d_%s", #relative_from_current, relative_from_current)
            })
        end
    end
    
    -- Sort completions by path length then alphabetical
    table.sort(completions, function(a, b)
        local a_len = #a.label
        local b_len = #b.label
        if a_len == b_len then
            return a.label < b.label
        end
        return a_len < b_len
    end)
    
    -- Limit results to prevent UI lag
    if #completions > 50 then
        local limited = {}
        for i = 1, 50 do
            table.insert(limited, completions[i])
        end
        completions = limited
    end
    
    -- Cache the results
    cache[cache_key] = {
        data = completions,
        timestamp = vim.loop.now()
    }
    
    return completions
end

-- Get tag completions using ripgrep
function M.get_tag_completions(query, root_dir)
    local cache_key = "tags_" .. (root_dir or "") .. "_" .. (query or "")
    
    -- Check cache first
    local cached = cache[cache_key]
    if cached and (vim.loop.now() - cached.timestamp) < cache_ttl then
        return cached.data
    end
    
    -- Use async function to extract tags, but we need to make it synchronous for completion
    local tags = {}
    local completed = false
    
    search.extract_tags_async(root_dir, function(extracted_tags, error)
        if error then
            -- Fallback to simple tags if extraction fails
            tags = {
                ["example"] = 1,
                ["todo"] = 1,
                ["project"] = 1
            }
        else
            tags = extracted_tags or {}
        end
        completed = true
    end)
    
    -- Wait for completion with timeout
    local timeout = 5000 -- 5 seconds
    local start_time = vim.loop.now()
    while not completed and (vim.loop.now() - start_time) < timeout do
        vim.wait(10) -- Wait 10ms between checks
    end
    
    if not completed then
        -- Timeout fallback
        tags = {
            ["example"] = 1,
            ["timeout"] = 1
        }
    end
    
    local completions = {}
    
    -- Convert tags to completion items
    for tag, count in pairs(tags) do
        -- Filter based on query if provided
        if not query or query == "" or tag:lower():match(query:lower()) then
            table.insert(completions, {
                label = tag,
                kind = vim.lsp.protocol.CompletionItemKind.Keyword,
                detail = string.format("Used %d times", count),
                insertText = tag,
                documentation = "Tag found in markdown files",
                sortText = string.format("%04d_%s", -count, tag) -- Sort by frequency (negative for desc)
            })
        end
    end
    
    -- Sort by frequency (most used first), then alphabetical
    table.sort(completions, function(a, b)
        -- Extract count from detail
        local a_count = tonumber(a.detail:match("(%d+)")) or 0
        local b_count = tonumber(b.detail:match("(%d+)")) or 0
        
        if a_count == b_count then
            return a.label < b.label
        end
        return a_count > b_count
    end)
    
    -- Limit results to prevent UI lag
    if #completions > 30 then
        local limited = {}
        for i = 1, 30 do
            table.insert(limited, completions[i])
        end
        completions = limited
    end
    
    -- If no tags found, provide helpful message
    if #completions == 0 then
        completions = {
            {
                label = "No tags found",
                kind = vim.lsp.protocol.CompletionItemKind.Text,
                detail = "Add #tags to your markdown files to see completions",
                insertText = "new-tag"
            }
        }
    end
    
    -- Cache the results
    cache[cache_key] = {
        data = completions,
        timestamp = vim.loop.now()
    }
    
    return completions
end

-- Setup function (for initialization)
function M.setup(config)
    config = config or {}
    if config.cache_ttl then
        cache_ttl = config.cache_ttl
    end
    if config.cache_max_size then
        cache_max_size = config.cache_max_size
    end
end

return M
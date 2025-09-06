-- Utility functions for completion system
local M = {}

-- Import the search module for ripgrep functionality
local search = require("pebble.search")

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
    
    -- Check for [[ pattern before cursor, anchored to end
    local before_cursor = line:sub(1, col)
    -- Look for the last [[ pattern that hasn't been closed
    local wiki_start = before_cursor:match(".*%[%[([^%]]*)$")
    
    if wiki_start ~= nil then  -- wiki_start can be empty string
        return true, wiki_start
    end
    
    return false, nil
end

function M.is_markdown_link_context()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    
    -- Check for ]( pattern before cursor, anchored to end
    local before_cursor = line:sub(1, col)
    -- Look for the last ]( pattern that hasn't been closed
    local link_start = before_cursor:match(".*%]%(([^%)]*)$")
    
    if link_start ~= nil then  -- link_start can be empty string
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
    
    -- Look for # followed by optional word characters at the end of the string
    -- This should match: "#", "#test", "#proj", etc.
    local tag_match = before_cursor:match("#([%w_/-]*)$")
    
    if tag_match ~= nil then  -- tag_match can be an empty string, which is valid
        return true, tag_match
    end
    
    return false, nil
end

-- Get root directory for searching
function M.get_root_dir()
    return search.get_root_dir()
end

-- Get wiki completions using ripgrep with recursive search and aliases
function M.get_wiki_completions(query, root_dir)
    local cache_key = "wiki_" .. (root_dir or "") .. "_" .. (query or "")
    
    -- Check cache first
    local cached = cache[cache_key]
    if cached and (vim.loop.now() - cached.timestamp) < cache_ttl then
        return cached.data
    end
    
    -- Find ALL markdown files recursively using ripgrep
    local markdown_files = {}
    
    -- Use ripgrep for recursive file discovery  
    if search.has_ripgrep() then
        -- Use ripgrep to find ALL .md files recursively
        local cmd = string.format(
            'rg --files --type md --hidden --follow %s 2>/dev/null || true',
            vim.fn.shellescape(root_dir or vim.fn.getcwd())
        )
        local output = vim.fn.system(cmd)
        if vim.v.shell_error == 0 and output and output ~= "" then
            for file_path in output:gmatch("[^\n]+") do
                if file_path and file_path ~= "" then
                    table.insert(markdown_files, file_path)
                end
            end
        end
    end
    
    -- Fallback to search module if ripgrep didn't work
    if #markdown_files == 0 then
        markdown_files = search.find_markdown_files_sync(root_dir) or {}
    end
    
    if #markdown_files == 0 then
        return {
            {
                label = "No markdown files found",
                kind = 1, -- Text kind
                detail = "Create .md files to see wiki link completions",
                insertText = "new-note"
            }
        }
    end
    
    -- Process each file to create completion items with aliases
    for _, file_path in ipairs(markdown_files) do
        local filename = vim.fn.fnamemodify(file_path, ":t:r") -- Get filename without extension
        local relative_path = vim.fn.fnamemodify(file_path, ":~:.")
        local dir_name = vim.fn.fnamemodify(file_path, ":h:t") -- Parent directory name
        
        -- Create multiple completion entries for different alias formats
        local aliases = {
            {
                label = filename,
                insertText = filename,
                detail = relative_path,
                alias_type = "filename"
            }
        }
        
        -- Add directory/filename format if file is in subdirectory
        if dir_name and dir_name ~= "." and dir_name ~= filename then
            table.insert(aliases, {
                label = dir_name .. "/" .. filename,
                insertText = filename, -- Still insert just the filename for wiki links
                detail = relative_path,
                alias_type = "dir/file"
            })
        end
        
        -- Add path-based alias for deep nested files
        local path_parts = {}
        for part in relative_path:gmatch("[^/]+") do
            if part ~= filename .. ".md" then -- Don't include the filename.md part
                table.insert(path_parts, part)
            end
        end
        if #path_parts > 1 then
            local path_alias = table.concat(path_parts, "/") .. "/" .. filename
            table.insert(aliases, {
                label = path_alias,
                insertText = filename,
                detail = relative_path,
                alias_type = "full_path"
            })
        end
        
        -- Process each alias
        for _, alias in ipairs(aliases) do
            local should_include = false
            local relevance_score = 0
        
            if not query or query == "" then
                -- No query, include all files
                should_include = true
                relevance_score = 1000 - #alias.label -- Prefer shorter aliases
            else
                local query_lower = query:lower()
                local label_lower = alias.label:lower()
                local filename_lower = filename:lower()
                local relative_lower = relative_path:lower()
                
                -- Bonus score based on alias type (filename preferred)
                local type_bonus = 0
                if alias.alias_type == "filename" then type_bonus = 1000
                elseif alias.alias_type == "dir/file" then type_bonus = 500
                else type_bonus = 100 end
                
                -- Check for exact matches (highest priority)
                if label_lower == query_lower or filename_lower == query_lower then
                    should_include = true
                    relevance_score = 10000 + type_bonus
                -- Check for starts with (high priority)  
                elseif label_lower:sub(1, #query_lower) == query_lower or filename_lower:sub(1, #query_lower) == query_lower then
                    should_include = true
                    relevance_score = 5000 + type_bonus + (1000 - #alias.label)
                -- Check for contains in label or filename (medium priority)
                elseif label_lower:find(query_lower, 1, true) or filename_lower:find(query_lower, 1, true) then
                    should_include = true
                    relevance_score = 3000 + type_bonus + (1000 - #alias.label)
                -- Check for contains in full relative path (lower priority)
                elseif relative_lower:find(query_lower, 1, true) then
                    should_include = true
                    relevance_score = 1500 + type_bonus + (1000 - #relative_path)
                -- Check for fuzzy matching (word boundaries)
                else
                    -- Split query into words and check if all words are found
                    local query_words = {}
                    for word in query_lower:gmatch("%w+") do
                        table.insert(query_words, word)
                    end
                    
                    if #query_words > 0 then
                        local all_words_found = true
                        local search_targets = { label_lower, filename_lower, relative_lower }
                        
                        for _, word in ipairs(query_words) do
                            local word_found = false
                            for _, target in ipairs(search_targets) do
                                if target:find(word, 1, true) then
                                    word_found = true
                                    break
                                end
                            end
                            if not word_found then
                                all_words_found = false
                                break
                            end
                        end
                        
                        if all_words_found then
                            should_include = true
                            relevance_score = 500 + type_bonus + (1000 - #alias.label)
                        end
                    end
                end
            end
            
            if should_include then
                table.insert(completions, {
                    label = alias.label,
                    kind = 17, -- File kind
                    detail = alias.detail,
                    insertText = alias.insertText,
                    documentation = "Wiki link to " .. alias.detail .. " (" .. alias.alias_type .. ")",
                    sortText = string.format("%05d_%s", 99999 - relevance_score, alias.label),
                    _relevance = relevance_score -- For debugging
                })
            end
        end
    end
    
    -- Sort completions by relevance score (highest first)
    table.sort(completions, function(a, b)
        local a_rel = a._relevance or 0
        local b_rel = b._relevance or 0
        if a_rel == b_rel then
            return a.label < b.label
        end
        return a_rel > b_rel
    end)
    
    -- Limit results to prevent UI lag, but be more generous with filtered results
    local max_results = 100
    if query and query ~= "" then
        -- For filtered results, be even more generous
        max_results = 150
    end
    
    if #completions > max_results then
        local limited = {}
        for i = 1, max_results do
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
                kind = 1, -- Text kind
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
                kind = 17, -- File kind
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
    
    -- Use simple ripgrep-based tag extraction for completion responsiveness  
    local tags = {}
    
    -- Try direct ripgrep command for faster tag extraction
    if search.has_ripgrep() then
        local cmd = string.format(
            'rg "#([a-zA-Z0-9_-]+)" --only-matching --no-filename --no-line-number %s 2>/dev/null | sort | uniq -c | sort -nr | head -50 || true',
            vim.fn.shellescape(root_dir or vim.fn.getcwd())
        )
        local output = vim.fn.system(cmd)
        if vim.v.shell_error == 0 and output and output ~= "" then
            for line in output:gmatch("[^\n]+") do
                local count, tag = line:match("^%s*(%d+)%s+#(.+)$")
                if count and tag then
                    tags[tag] = tonumber(count) or 1
                end
            end
        end
    end
    
    -- If direct ripgrep didn't work, try the search module async function with very short timeout
    if vim.tbl_isempty(tags) then
        local completed = false
        search.extract_tags_async(root_dir, function(extracted_tags, error)
            if not error and extracted_tags then
                tags = extracted_tags
            end
            completed = true
        end)
        
        -- Very short wait for async function
        local timeout = 200 -- 200ms max
        local start_time = vim.loop.now()
        while not completed and (vim.loop.now() - start_time) < timeout do
            vim.wait(10, function() return completed end)
        end
    end
    
    -- If still no tags, provide sensible fallbacks  
    if vim.tbl_isempty(tags) then
        tags = {
            ["todo"] = 1,
            ["project"] = 1,
            ["note"] = 1,  
            ["idea"] = 1,
            ["important"] = 1,
            ["work"] = 1,
            ["personal"] = 1
        }
    end
    
    local completions = {}
    
    -- Convert tags to completion items
    for tag, count in pairs(tags) do
        -- Filter based on query if provided
        if not query or query == "" or tag:lower():match(query:lower()) then
            table.insert(completions, {
                label = tag,
                kind = 14, -- Keyword kind
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
                kind = 1, -- Text kind
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
-- Utility functions for completion system
local M = {}

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

-- Get root directory for searching
function M.get_root_dir()
    -- Try to find git root first
    local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
    if vim.v.shell_error == 0 and git_root ~= "" then
        return git_root
    end
    
    -- Fall back to current working directory
    return vim.fn.getcwd()
end

-- Get wiki completions (safe stub implementation)
function M.get_wiki_completions(query, root_dir)
    -- Return basic example completions for now
    return {
        {
            label = "Example Wiki Link",
            kind = vim.lsp.protocol.CompletionItemKind.Reference,
            detail = "Example wiki page",
            insertText = "Example Wiki Link"
        }
    }
end

-- Get markdown link completions (safe stub implementation)
function M.get_markdown_link_completions(query, root_dir)
    -- Return basic example completions for now
    return {
        {
            label = "./example.md",
            kind = vim.lsp.protocol.CompletionItemKind.File,
            detail = "Example markdown file",
            insertText = "./example.md"
        }
    }
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
-- Simple test script for pebble completion functionality
-- Run this script in a directory with some .md files to test completion

local completion = require('pebble.completion')

-- Test 1: Basic completion functionality
print("=== Test 1: Basic Completion ===")
local root_dir = completion.get_root_dir()
print("Root directory: " .. root_dir)

local completions = completion.get_wiki_completions("", root_dir)
print("Total notes found: " .. #completions)

-- Show first 5 completions
for i = 1, math.min(5, #completions) do
    local comp = completions[i]
    print(string.format("  %d. %s (%s)", i, comp.label, comp.detail))
end

-- Test 2: Fuzzy matching
print("\n=== Test 2: Fuzzy Matching ===")
local test_queries = {"test", "comp", "lua", "md"}

for _, query in ipairs(test_queries) do
    local matches = completion.get_wiki_completions(query, root_dir)
    print(string.format("Query '%s': %d matches", query, #matches))
    
    -- Show top 3 matches with scores
    for i = 1, math.min(3, #matches) do
        local comp = matches[i]
        print(string.format("  %d. %s (score: %.1f)", i, comp.label, comp.score))
    end
end

-- Test 3: Wiki link context detection
print("\n=== Test 3: Wiki Link Context Detection ===")

-- Simulate different cursor positions and line content
local test_cases = {
    { line = "This is a [[test]] link", col = 12, expected = true },
    { line = "This is a [[test", col = 15, expected = true },
    { line = "This is a test]] link", col = 10, expected = false },
    { line = "[[", col = 2, expected = true },
    { line = "Not a wiki link", col = 5, expected = false },
    { line = "[[Note Name|Display Text]]", col = 8, expected = true },
}

-- Mock vim API for testing
local original_get_line = vim.api.nvim_get_current_line
local original_get_cursor = vim.api.nvim_win_get_cursor

for i, test_case in ipairs(test_cases) do
    -- Mock the vim API calls
    vim.api.nvim_get_current_line = function() return test_case.line end
    vim.api.nvim_win_get_cursor = function() return {1, test_case.col} end
    
    local is_wiki, query = completion.is_wiki_link_context()
    local result = is_wiki == test_case.expected and "✓" or "✗"
    
    print(string.format("  Test %d: %s | Line: '%s' | Col: %d | Expected: %s | Got: %s | Query: '%s'", 
        i, result, test_case.line, test_case.col, tostring(test_case.expected), tostring(is_wiki), query))
end

-- Restore original functions
vim.api.nvim_get_current_line = original_get_line
vim.api.nvim_win_get_cursor = original_get_cursor

-- Test 4: Cache functionality
print("\n=== Test 4: Cache Functionality ===")

-- Clear cache
completion.invalidate_cache()
print("Cache invalidated")

-- Time first load
local start_time = vim.loop.hrtime()
local first_load = completion.get_wiki_completions("", root_dir)
local first_time = (vim.loop.hrtime() - start_time) / 1e6 -- Convert to milliseconds

print(string.format("First load: %.2f ms (%d items)", first_time, #first_load))

-- Time cached load
start_time = vim.loop.hrtime()
local cached_load = completion.get_wiki_completions("", root_dir)
local cached_time = (vim.loop.hrtime() - start_time) / 1e6

print(string.format("Cached load: %.2f ms (%d items)", cached_time, #cached_load))
print(string.format("Cache speedup: %.1fx", first_time / math.max(cached_time, 0.01)))

-- Test 5: Error handling
print("\n=== Test 5: Error Handling ===")

-- Test with non-existent directory
local bad_completions = completion.get_wiki_completions("test", "/non/existent/directory")
print("Non-existent directory: " .. #bad_completions .. " completions (should be 0)")

-- Test with nil query
local nil_completions = completion.get_wiki_completions(nil, root_dir)
print("Nil query: " .. #nil_completions .. " completions")

print("\n=== Test Complete ===")
print("Run ':PebbleComplete' in a markdown file with '[[' to test interactively")
print("Run ':PebbleCompletionStats' to see current cache statistics")
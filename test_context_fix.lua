-- Test the fixed context detection
local utils = require("pebble.completion.utils")

print("=== Testing Fixed Context Detection ===")

-- Mock vim APIs
vim.api = vim.api or {}

-- Test cases for wiki link detection
local wiki_tests = {
    { line = "Link to [[example", cursor = 17, expected = true, expected_query = "example" },
    { line = "Link to [[", cursor = 10, expected = true, expected_query = "" },
    { line = "Previous [[old]] and [[new", cursor = 23, expected = true, expected_query = "new" },
    { line = "No wiki link here", cursor = 17, expected = false }
}

print("\n1. Wiki Link Context Tests:")
for i, test in ipairs(wiki_tests) do
    vim.api.nvim_get_current_line = function() return test.line end
    vim.api.nvim_win_get_cursor = function() return {1, test.cursor} end
    
    local is_wiki, query = utils.is_wiki_link_context()
    local success = (is_wiki == test.expected) and (query == test.expected_query)
    
    print(string.format("  Test %d: %s", i, success and "✓" or "✗"))
    print(string.format("    Line: '%s' (cursor at %d)", test.line, test.cursor))
    print(string.format("    Expected: is_wiki=%s, query='%s'", tostring(test.expected), test.expected_query or ""))
    print(string.format("    Got: is_wiki=%s, query='%s'", tostring(is_wiki), query or ""))
    print()
end

-- Test cases for markdown link detection  
local md_tests = {
    { line = "Check [text](./file", cursor = 19, expected = true, expected_query = "./file" },
    { line = "Link [text](", cursor = 12, expected = true, expected_query = "" },
    { line = "Old [a](old.md) new [b](new", cursor = 27, expected = true, expected_query = "new" }
}

print("2. Markdown Link Context Tests:")
for i, test in ipairs(md_tests) do
    vim.api.nvim_get_current_line = function() return test.line end
    vim.api.nvim_win_get_cursor = function() return {1, test.cursor} end
    
    local is_md, query = utils.is_markdown_link_context()
    local success = (is_md == test.expected) and (query == test.expected_query)
    
    print(string.format("  Test %d: %s", i, success and "✓" or "✗"))
    print(string.format("    Line: '%s' (cursor at %d)", test.line, test.cursor))
    print(string.format("    Expected: is_md=%s, query='%s'", tostring(test.expected), test.expected_query or ""))
    print(string.format("    Got: is_md=%s, query='%s'", tostring(is_md), query or ""))
    print()
end

print("=== Context Detection Tests Complete ===")
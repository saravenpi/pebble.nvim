-- Test script for tag context detection
local utils = require("pebble.completion.utils")

-- Test different scenarios
local test_cases = {
    { line = "This is a #test", cursor_pos = 15, expected = true, expected_query = "test" },
    { line = "This is a #", cursor_pos = 11, expected = true, expected_query = "" },
    { line = "# heading", cursor_pos = 1, expected = true, expected_query = "" },
    { line = "No tag here", cursor_pos = 11, expected = false },
    { line = "This #part and more", cursor_pos = 10, expected = true, expected_query = "part" },
}

print("Testing tag context detection:")
print("==============================")

for i, test in ipairs(test_cases) do
    -- Mock vim APIs for testing
    vim.api = vim.api or {}
    vim.api.nvim_get_current_line = function() return test.line end
    vim.api.nvim_win_get_cursor = function() return {1, test.cursor_pos} end
    
    local is_tag, query = utils.is_tag_context()
    
    local status = "✓"
    if is_tag ~= test.expected then
        status = "✗ Expected " .. tostring(test.expected) .. ", got " .. tostring(is_tag)
    elseif is_tag and query ~= test.expected_query then
        status = "✗ Expected query '" .. test.expected_query .. "', got '" .. (query or "nil") .. "'"
    end
    
    print(string.format("Test %d: %s", i, status))
    print(string.format("  Line: '%s' (cursor at %d)", test.line, test.cursor_pos))
    print(string.format("  Result: is_tag=%s, query='%s'", tostring(is_tag), query or "nil"))
    print()
end

-- Test tag completion
print("Testing tag completion:")
print("=======================")
local root_dir = "/Users/yannthevenin/code/Perso/Saravenpi/pebble.nvim"
local completions = utils.get_tag_completions("", root_dir)
print("Found " .. #completions .. " tag completions:")
for i, comp in ipairs(completions) do
    if i <= 5 then  -- Show first 5
        print(string.format("  %d. %s (%s)", i, comp.label, comp.detail))
    end
end
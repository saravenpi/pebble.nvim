-- Direct test of completion functions
local utils = require("pebble.completion.utils")

print("=== Testing Completion Functions Directly ===")

-- Test tag completion
print("\n1. Testing tag completion:")
local tags = utils.get_tag_completions("", "/Users/yannthevenin/code/Perso/Saravenpi/pebble.nvim")
print("Tags found:", #tags)
for i = 1, math.min(3, #tags) do
    print("  - " .. tags[i].label .. " (" .. tags[i].detail .. ")")
end

-- Test wiki link completion  
print("\n2. Testing wiki link completion:")
local wiki = utils.get_wiki_completions("", "/Users/yannthevenin/code/Perso/Saravenpi/pebble.nvim")
print("Wiki links found:", #wiki)
for i = 1, math.min(3, #wiki) do
    print("  - " .. wiki[i].label .. " -> " .. wiki[i].detail)
end

-- Test context detection
print("\n3. Testing context detection:")

-- Mock vim APIs for testing
vim.api = vim.api or {}
vim.api.nvim_get_current_line = function() return "This is a #test tag" end
vim.api.nvim_win_get_cursor = function() return {1, 16} end  -- Cursor after "#test"

local is_tag, tag_query = utils.is_tag_context()
print("Tag context test: is_tag=" .. tostring(is_tag) .. ", query='" .. (tag_query or "nil") .. "'")

-- Test wiki context  
vim.api.nvim_get_current_line = function() return "Link to [[some-note" end
vim.api.nvim_win_get_cursor = function() return {1, 18} end

local is_wiki, wiki_query = utils.is_wiki_link_context()
print("Wiki context test: is_wiki=" .. tostring(is_wiki) .. ", query='" .. (wiki_query or "nil") .. "'")

print("\n=== Test Complete ===")
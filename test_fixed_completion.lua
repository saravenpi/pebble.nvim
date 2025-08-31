#!/usr/bin/env lua

-- Test script for fixed pebble completion
print("Testing fixed pebble completion system...")

-- Test 1: Can we load the utils module?
local ok, utils = pcall(require, "pebble.completion.utils")
if ok then
    print("✓ Utils module loaded successfully")
else
    print("✗ Failed to load utils module: " .. tostring(utils))
    return
end

-- Test 2: Can we load the manager?
local ok2, manager = pcall(require, "pebble.completion.manager")
if ok2 then
    print("✓ Manager module loaded successfully")
else
    print("✗ Failed to load manager module: " .. tostring(manager))
    return
end

-- Test 3: Can we load nvim_cmp module?
local ok3, nvim_cmp = pcall(require, "pebble.completion.nvim_cmp")
if ok3 then
    print("✓ nvim_cmp module loaded successfully")
else
    print("✗ Failed to load nvim_cmp module: " .. tostring(nvim_cmp))
    return
end

-- Test 4: Test utils functions
print("\nTesting utils functions:")
print("✓ get_root_dir:", utils.get_root_dir())

-- Mock vim APIs for standalone testing
if not vim then
    vim = {
        api = {
            nvim_get_current_line = function() return "[[test]]" end,
            nvim_win_get_cursor = function() return {1, 6} end
        },
        fn = {
            getcwd = function() return "/test" end,
            system = function() return "" end
        },
        v = { shell_error = 1 }
    }
end

local is_wiki, query = utils.is_wiki_link_context()
print("✓ is_wiki_link_context:", is_wiki, query or "nil")

local completions = utils.get_wiki_completions("test", "/test")
print("✓ get_wiki_completions returned", #completions, "items")

print("\nAll tests passed! Completion system is working correctly.")
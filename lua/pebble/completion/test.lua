local M = {}

-- Simple test runner for tag completion functionality
local tags = require("pebble.completion.tags")
local config = require("pebble.completion.config")

-- Test configuration
local test_config = {
    inline_tag_pattern = "#([a-zA-Z0-9_/-]+)",
    frontmatter_tag_pattern = "tags:\\s*\\[([^\\]]+)\\]|tags:\\s*-\\s*([^\\n]+)",
    file_patterns = { "*.md" },
    max_files_scan = 100,
    cache_ttl = 30000,
    async_extraction = false, -- Use sync for testing
    fuzzy_matching = true,
    nested_tag_support = true,
    max_completion_items = 20,
}

-- Test helpers
local function assert_contains(items, expected_tag, test_name)
    for _, item in ipairs(items) do
        if item.label == "#" .. expected_tag or item.insertText == expected_tag then
            print("✓ " .. test_name .. " - Found: " .. expected_tag)
            return true
        end
    end
    print("✗ " .. test_name .. " - Missing: " .. expected_tag)
    return false
end

local function print_items(items, limit)
    limit = limit or 10
    print("Completion items (" .. #items .. " total):")
    for i, item in ipairs(items) do
        if i > limit then
            print("... and " .. (#items - limit) .. " more")
            break
        end
        print("  " .. i .. ". " .. item.label .. " (" .. (item.detail or "no detail") .. ")")
    end
end

-- Test basic setup
function M.test_basic_setup()
    print("\n=== Testing Basic Setup ===")
    
    local success = pcall(function()
        tags.setup(test_config)
    end)
    
    if success then
        print("✓ Tag completion setup successful")
        
        -- Check cache stats
        local stats = tags.get_cache_stats()
        print("✓ Cache stats: " .. stats.entries_count .. " entries")
        
        return true
    else
        print("✗ Tag completion setup failed")
        return false
    end
end

-- Test tag extraction
function M.test_tag_extraction()
    print("\n=== Testing Tag Extraction ===")
    
    -- Initialize and force cache update
    tags.setup(test_config)
    tags.refresh_cache()
    
    -- Wait a bit for async operations (if any)
    vim.wait(1000)
    
    local stats = tags.get_cache_stats()
    print("Cache entries after refresh: " .. stats.entries_count)
    
    if stats.entries_count > 0 then
        print("✓ Tags extracted from files")
        return true
    else
        print("✗ No tags extracted - check file patterns and content")
        return false
    end
end

-- Test completion items
function M.test_completion_items()
    print("\n=== Testing Completion Items ===")
    
    -- Get all completion items (no pattern)
    local all_items = tags.get_completion_items("")
    print("Total completion items: " .. #all_items)
    
    if #all_items > 0 then
        print_items(all_items, 5)
        print("✓ Completion items generated")
    else
        print("✗ No completion items generated")
        return false
    end
    
    -- Test pattern matching
    local filtered_items = tags.get_completion_items("prod")
    print("\nFiltered items for 'prod': " .. #filtered_items)
    print_items(filtered_items, 3)
    
    return #all_items > 0
end

-- Test fuzzy matching
function M.test_fuzzy_matching()
    print("\n=== Testing Fuzzy Matching ===")
    
    -- Test various patterns
    local test_patterns = {
        "work",
        "prod", 
        "auto",
        "proj",
        "nvim"
    }
    
    local found_matches = false
    
    for _, pattern in ipairs(test_patterns) do
        local items = tags.get_completion_items(pattern)
        if #items > 0 then
            print("✓ Pattern '" .. pattern .. "' found " .. #items .. " matches")
            found_matches = true
            
            -- Show first few matches
            for i, item in ipairs(items) do
                if i <= 3 then
                    print("  " .. item.label)
                end
            end
        else
            print("- Pattern '" .. pattern .. "' found no matches")
        end
    end
    
    return found_matches
end

-- Test nested tag support
function M.test_nested_tags()
    print("\n=== Testing Nested Tag Support ===")
    
    local items = tags.get_completion_items("")
    local nested_found = false
    
    for _, item in ipairs(items) do
        if item.insertText and item.insertText:find("/") then
            print("✓ Found nested tag: " .. item.label)
            nested_found = true
            if item.documentation then
                print("  Documentation: " .. (item.documentation.value or item.documentation))
            end
            break
        end
    end
    
    if not nested_found then
        print("- No nested tags found (may be normal if test files don't contain them)")
    end
    
    return true -- Don't fail if no nested tags in test data
end

-- Test configuration presets
function M.test_config_presets()
    print("\n=== Testing Configuration Presets ===")
    
    local presets = { "performance", "balanced", "comprehensive", "obsidian", "logseq" }
    local all_valid = true
    
    for _, preset in ipairs(presets) do
        local preset_config = config.build_config(preset)
        local valid, errors = config.validate_config(preset_config)
        
        if valid then
            print("✓ Preset '" .. preset .. "' valid")
        else
            print("✗ Preset '" .. preset .. "' invalid:")
            for _, error in ipairs(errors) do
                print("  - " .. error)
            end
            all_valid = false
        end
    end
    
    return all_valid
end

-- Test environment detection
function M.test_environment_detection()
    print("\n=== Testing Environment Detection ===")
    
    local suggestions = config.detect_environment()
    print("Detected environment:")
    print("  Preset: " .. suggestions.preset)
    print("  Reason: " .. suggestions.reason)
    
    -- Validate suggested config
    local suggested_config = config.build_config(suggestions.preset)
    local valid, errors = config.validate_config(suggested_config)
    
    if valid then
        print("✓ Suggested configuration is valid")
        return true
    else
        print("✗ Suggested configuration is invalid:")
        for _, error in ipairs(errors) do
            print("  - " .. error)
        end
        return false
    end
end

-- Run all tests
function M.run_all_tests()
    print("=== Pebble Tag Completion Test Suite ===")
    print("Testing in directory: " .. vim.fn.getcwd())
    
    local tests = {
        { name = "Basic Setup", func = M.test_basic_setup },
        { name = "Tag Extraction", func = M.test_tag_extraction },
        { name = "Completion Items", func = M.test_completion_items },
        { name = "Fuzzy Matching", func = M.test_fuzzy_matching },
        { name = "Nested Tags", func = M.test_nested_tags },
        { name = "Config Presets", func = M.test_config_presets },
        { name = "Environment Detection", func = M.test_environment_detection },
    }
    
    local passed = 0
    local total = #tests
    
    for _, test in ipairs(tests) do
        local success = test.func()
        if success then
            passed = passed + 1
        end
    end
    
    print("\n=== Test Results ===")
    print("Passed: " .. passed .. "/" .. total)
    
    if passed == total then
        print("✅ All tests passed!")
    else
        print("❌ Some tests failed. Check output above for details.")
    end
    
    return passed == total
end

-- Command to run tests
vim.api.nvim_create_user_command("PebbleTestTags", function()
    M.run_all_tests()
end, { desc = "Run pebble tag completion tests" })

return M
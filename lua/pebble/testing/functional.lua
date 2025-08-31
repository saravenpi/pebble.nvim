-- Functional Testing Suite
-- Tests for completion accuracy, fuzzy matching, and cache behavior
local M = {}

local completion = require("pebble.completion")

-- Test state
local test_state = {
    current_test = nil,
    results = {},
    temp_directory = nil
}

-- Logging utilities
local function log_info(msg)
    print("[PEBBLE FUNCTIONAL] " .. msg)
end

local function log_error(msg)
    print("[PEBBLE FUNCTIONAL ERROR] " .. msg)
end

-- Test environment setup
local function setup_test_files()
    local temp_dir = vim.fn.tempname() .. "_pebble_functional"
    vim.fn.mkdir(temp_dir, "p")
    
    -- Create test files with various content types
    local test_files = {
        {
            filename = "programming-concepts.md",
            content = {
                "---",
                "title: Programming Concepts",
                "aliases: [\"coding\", \"development\", \"prog\"]",
                "tags: [\"programming\", \"concepts\"]",
                "---",
                "",
                "# Programming Concepts",
                "",
                "This note covers various [[algorithm design]] patterns.",
                "",
                "See also: [data structures](data-structures.md)",
                "",
                "#programming #algorithms #design-patterns"
            }
        },
        {
            filename = "algorithm-design.md", 
            content = {
                "---",
                "title: Algorithm Design",
                "aliases: [\"algorithms\", \"algo\"]",
                "tags: [\"algorithms\", \"design\"]",
                "---",
                "",
                "# Algorithm Design",
                "",
                "Back to [[programming-concepts]].",
                "",
                "#algorithms #complexity"
            }
        },
        {
            filename = "data-structures.md",
            content = {
                "---",
                "title: Data Structures",
                "aliases: [\"DS\", \"structures\"]",
                "tags: [\"data\", \"structures\"]",
                "---",
                "",
                "# Data Structures",
                "",
                "Related to [[algorithm-design]] and [[programming-concepts]].",
                "",
                "#data-structures #programming"
            }
        },
        {
            filename = "machine-learning.md",
            content = {
                "---",
                "title: Machine Learning",
                "aliases: [\"ML\", \"ai\", \"artificial intelligence\"]",
                "tags: [\"ml\", \"ai\", \"learning\"]",
                "---",
                "",
                "# Machine Learning",
                "",
                "Uses [[algorithm-design]] and [[data-structures]].",
                "",
                "#machine-learning #ai #algorithms"
            }
        },
        {
            filename = "project/nested-file.md",
            content = {
                "---",
                "title: Nested File",
                "aliases: [\"nested\"]",
                "tags: [\"nested\", \"organization\"]",
                "---",
                "",
                "# Nested File",
                "",
                "This is in a subdirectory.",
                "",
                "Links to [[programming-concepts]].",
                "",
                "#organization #structure"
            }
        }
    }
    
    for _, file_info in ipairs(test_files) do
        local filepath = temp_dir .. "/" .. file_info.filename
        local dir = vim.fn.fnamemodify(filepath, ":h")
        
        if vim.fn.isdirectory(dir) == 0 then
            vim.fn.mkdir(dir, "p")
        end
        
        vim.fn.writefile(file_info.content, filepath)
    end
    
    test_state.temp_directory = temp_dir
    return temp_dir
end

local function cleanup_test_files()
    if test_state.temp_directory and vim.fn.isdirectory(test_state.temp_directory) == 1 then
        vim.fn.delete(test_state.temp_directory, "rf")
        test_state.temp_directory = nil
    end
end

-- Wiki Link Completion Accuracy Tests
local function test_wiki_link_exact_match()
    test_state.current_test = "wiki_exact_match"
    
    local results = completion.get_wiki_completions("programming-concepts", test_state.temp_directory)
    
    local exact_match_found = false
    local exact_match_first = false
    
    for i, item in ipairs(results) do
        if item.label == "programming-concepts" then
            exact_match_found = true
            if i == 1 then
                exact_match_first = true
            end
            break
        end
    end
    
    local passed = exact_match_found and exact_match_first
    
    test_state.results.wiki_exact_match = {
        passed = passed,
        exact_match_found = exact_match_found,
        exact_match_first = exact_match_first,
        total_results = #results
    }
    
    return passed
end

local function test_wiki_link_alias_matching()
    test_state.current_test = "wiki_alias_matching"
    
    -- Test various aliases
    local alias_tests = {
        { query = "coding", expected = "programming-concepts" },
        { query = "algo", expected = "algorithm-design" },
        { query = "DS", expected = "data-structures" },
        { query = "ML", expected = "machine-learning" }
    }
    
    local passed_tests = 0
    local alias_results = {}
    
    for _, test_case in ipairs(alias_tests) do
        local results = completion.get_wiki_completions(test_case.query, test_state.temp_directory)
        
        local found = false
        for _, item in ipairs(results) do
            -- Check if the expected filename is found
            local filename = item.note_metadata and item.note_metadata.filename or item.label
            if filename == test_case.expected then
                found = true
                break
            end
        end
        
        alias_results[test_case.query] = {
            found = found,
            expected = test_case.expected,
            results_count = #results
        }
        
        if found then
            passed_tests = passed_tests + 1
        end
    end
    
    local all_passed = passed_tests == #alias_tests
    
    test_state.results.wiki_alias_matching = {
        passed = all_passed,
        passed_count = passed_tests,
        total_count = #alias_tests,
        alias_results = alias_results
    }
    
    return all_passed
end

local function test_wiki_link_title_matching()
    test_state.current_test = "wiki_title_matching"
    
    -- Test title matching
    local title_tests = {
        { query = "Programming", expected = "programming-concepts" },
        { query = "Algorithm", expected = "algorithm-design" },
        { query = "Machine", expected = "machine-learning" },
        { query = "Nested", expected = "nested-file" }
    }
    
    local passed_tests = 0
    local title_results = {}
    
    for _, test_case in ipairs(title_tests) do
        local results = completion.get_wiki_completions(test_case.query, test_state.temp_directory)
        
        local found = false
        for _, item in ipairs(results) do
            local filename = item.note_metadata and item.note_metadata.filename or item.label
            if filename == test_case.expected then
                found = true
                break
            end
        end
        
        title_results[test_case.query] = {
            found = found,
            expected = test_case.expected,
            results_count = #results
        }
        
        if found then
            passed_tests = passed_tests + 1
        end
    end
    
    local all_passed = passed_tests == #title_tests
    
    test_state.results.wiki_title_matching = {
        passed = all_passed,
        passed_count = passed_tests,
        total_count = #title_tests,
        title_results = title_results
    }
    
    return all_passed
end

-- Fuzzy Matching Quality Tests
local function test_fuzzy_matching_quality()
    test_state.current_test = "fuzzy_matching_quality"
    
    -- Test fuzzy matching with various patterns
    local fuzzy_tests = {
        { query = "prog", expected_in_results = {"programming-concepts"} },
        { query = "algo", expected_in_results = {"algorithm-design"} },
        { query = "ml", expected_in_results = {"machine-learning"} },
        { query = "data", expected_in_results = {"data-structures"} },
        { query = "nest", expected_in_results = {"nested-file"} }
    }
    
    local passed_tests = 0
    local fuzzy_results = {}
    
    for _, test_case in ipairs(fuzzy_tests) do
        local results = completion.get_wiki_completions(test_case.query, test_state.temp_directory)
        
        local found_count = 0
        local found_items = {}
        
        for _, expected in ipairs(test_case.expected_in_results) do
            for _, item in ipairs(results) do
                local filename = item.note_metadata and item.note_metadata.filename or item.label
                if filename == expected then
                    found_count = found_count + 1
                    table.insert(found_items, expected)
                    break
                end
            end
        end
        
        local success = found_count == #test_case.expected_in_results
        
        fuzzy_results[test_case.query] = {
            success = success,
            found_count = found_count,
            expected_count = #test_case.expected_in_results,
            found_items = found_items,
            total_results = #results
        }
        
        if success then
            passed_tests = passed_tests + 1
        end
    end
    
    local all_passed = passed_tests == #fuzzy_tests
    
    test_state.results.fuzzy_matching_quality = {
        passed = all_passed,
        passed_count = passed_tests,
        total_count = #fuzzy_tests,
        fuzzy_results = fuzzy_results
    }
    
    return all_passed
end

-- Tag Completion Tests  
local function test_tag_completion()
    test_state.current_test = "tag_completion"
    
    -- Check if tag completion module is available
    local tag_completion_available = pcall(require, "pebble.completion.tags")
    
    if not tag_completion_available then
        test_state.results.tag_completion = {
            passed = true,  -- Pass if not available (optional feature)
            available = false,
            message = "Tag completion module not available - skipping test"
        }
        return true
    end
    
    local tags = require("pebble.completion.tags")
    
    -- Test tag completion functionality
    local success, tag_results = pcall(function()
        -- This would need to be implemented based on the actual tag completion API
        return tags.get_completions("#prog", test_state.temp_directory)
    end)
    
    test_state.results.tag_completion = {
        passed = success,
        available = tag_completion_available,
        success = success,
        error = success and nil or tag_results
    }
    
    return success
end

-- Cache Invalidation Tests
local function test_cache_invalidation()
    test_state.current_test = "cache_invalidation"
    
    -- Get initial results
    local initial_results = completion.get_wiki_completions("programming", test_state.temp_directory)
    local initial_count = #initial_results
    
    -- Invalidate cache
    completion.invalidate_cache()
    
    -- Get results again (should rebuild cache)
    local post_invalidation_results = completion.get_wiki_completions("programming", test_state.temp_directory)
    local post_invalidation_count = #post_invalidation_results
    
    -- Add a new file to test cache update detection
    local new_file = test_state.temp_directory .. "/new-programming-file.md"
    local new_content = {
        "---",
        "title: New Programming File",
        "aliases: [\"new-prog\"]",
        "tags: [\"programming\", \"new\"]",
        "---",
        "",
        "# New Programming File",
        "",
        "This is a new file for testing cache invalidation.",
        "",
        "#programming #testing"
    }
    
    vim.fn.writefile(new_content, new_file)
    
    -- Invalidate cache again
    completion.invalidate_cache()
    
    -- Get results with new file
    local final_results = completion.get_wiki_completions("programming", test_state.temp_directory)
    local final_count = #final_results
    
    -- Check if new file is included
    local new_file_found = false
    for _, item in ipairs(final_results) do
        local filename = item.note_metadata and item.note_metadata.filename or item.label
        if filename == "new-programming-file" then
            new_file_found = true
            break
        end
    end
    
    local passed = (initial_count == post_invalidation_count) and 
                   (final_count > initial_count) and 
                   new_file_found
    
    test_state.results.cache_invalidation = {
        passed = passed,
        initial_count = initial_count,
        post_invalidation_count = post_invalidation_count,
        final_count = final_count,
        new_file_found = new_file_found
    }
    
    return passed
end

-- Context Detection Tests
local function test_context_detection()
    test_state.current_test = "context_detection"
    
    -- Mock vim API calls for testing context detection
    local original_get_current_line = vim.api.nvim_get_current_line
    local original_get_cursor = vim.api.nvim_win_get_cursor
    
    local test_cases = {
        {
            name = "wiki_link_context",
            line = "This is a [[test",
            cursor_col = 14, -- Position after "[[test"
            expected_wiki = true,
            expected_markdown = false
        },
        {
            name = "markdown_link_context", 
            line = "This is a [link](test",
            cursor_col = 20, -- Position after "]("test"
            expected_wiki = false,
            expected_markdown = true
        },
        {
            name = "no_link_context",
            line = "This is just text",
            cursor_col = 10,
            expected_wiki = false,
            expected_markdown = false
        }
    }
    
    local passed_tests = 0
    local context_results = {}
    
    for _, test_case in ipairs(test_cases) do
        -- Mock the vim API calls
        vim.api.nvim_get_current_line = function()
            return test_case.line
        end
        
        vim.api.nvim_win_get_cursor = function()
            return {1, test_case.cursor_col}
        end
        
        -- Test context detection
        local is_wiki, wiki_query = completion.is_wiki_link_context()
        local is_markdown, markdown_query = completion.is_markdown_link_context()
        
        local wiki_correct = is_wiki == test_case.expected_wiki
        local markdown_correct = is_markdown == test_case.expected_markdown
        local test_passed = wiki_correct and markdown_correct
        
        context_results[test_case.name] = {
            passed = test_passed,
            wiki_detected = is_wiki,
            wiki_expected = test_case.expected_wiki,
            markdown_detected = is_markdown, 
            markdown_expected = test_case.expected_markdown,
            wiki_query = wiki_query,
            markdown_query = markdown_query
        }
        
        if test_passed then
            passed_tests = passed_tests + 1
        end
    end
    
    -- Restore original vim API calls
    vim.api.nvim_get_current_line = original_get_current_line
    vim.api.nvim_win_get_cursor = original_get_cursor
    
    local all_passed = passed_tests == #test_cases
    
    test_state.results.context_detection = {
        passed = all_passed,
        passed_count = passed_tests,
        total_count = #test_cases,
        context_results = context_results
    }
    
    return all_passed
end

-- Main functional test runner
function M.run_functional_tests()
    log_info("Starting functional testing suite")
    
    local test_dir = setup_test_files()
    if not test_dir then
        log_error("Failed to setup test environment")
        return false
    end
    
    local tests = {
        test_wiki_link_exact_match,
        test_wiki_link_alias_matching,
        test_wiki_link_title_matching,
        test_fuzzy_matching_quality,
        test_tag_completion,
        test_cache_invalidation,
        test_context_detection
    }
    
    local passed_count = 0
    local total_count = #tests
    
    for _, test_func in ipairs(tests) do
        local success, result = pcall(test_func)
        if success and result then
            passed_count = passed_count + 1
            log_info("✓ " .. test_state.current_test)
        elseif success and not result then
            log_info("✗ " .. test_state.current_test)
        else
            log_error("✗ " .. test_state.current_test .. " (crashed): " .. (result or "unknown error"))
        end
    end
    
    cleanup_test_files()
    
    local all_passed = passed_count == total_count
    log_info("Functional testing completed: " .. passed_count .. "/" .. total_count .. " tests passed")
    
    return all_passed, {
        passed = passed_count,
        total = total_count,
        results = test_state.results
    }
end

-- Get test results
function M.get_results()
    return test_state.results
end

return M
-- Integration Testing Framework
-- Tests for nvim-cmp compatibility, multiple sources, filetype switching, and error recovery
local M = {}

-- Test state
local test_state = {
    current_test = nil,
    results = {},
    temp_directory = nil,
    original_filetype = nil,
    test_buffer = nil
}

-- Logging utilities
local function log_info(msg)
    print("[PEBBLE INTEGRATION] " .. msg)
end

local function log_error(msg)
    print("[PEBBLE INTEGRATION ERROR] " .. msg)
end

-- Test environment setup
local function setup_integration_test_env()
    local temp_dir = vim.fn.tempname() .. "_pebble_integration"
    vim.fn.mkdir(temp_dir, "p")
    
    -- Create test files
    local test_files = {
        {
            filename = "test-integration.md",
            content = {
                "---",
                "title: Integration Test Note",
                "aliases: [\"integration\", \"test-note\"]", 
                "tags: [\"test\", \"integration\"]",
                "---",
                "",
                "# Integration Test Note",
                "",
                "This note tests [[completion integration]].",
                "",
                "Link to [another note](another-note.md).",
                "",
                "#integration-test #completion"
            }
        },
        {
            filename = "another-note.md",
            content = {
                "---",
                "title: Another Note",
                "aliases: [\"another\"]",
                "tags: [\"test\"]",
                "---",
                "",
                "# Another Note",
                "",
                "Back to [[test-integration]].",
                "",
                "#test-note"
            }
        }
    }
    
    for _, file_info in ipairs(test_files) do
        local filepath = temp_dir .. "/" .. file_info.filename
        vim.fn.writefile(file_info.content, filepath)
    end
    
    test_state.temp_directory = temp_dir
    return temp_dir
end

local function cleanup_integration_test_env()
    -- Restore original filetype if changed
    if test_state.original_filetype and test_state.test_buffer then
        pcall(vim.api.nvim_buf_set_option, test_state.test_buffer, 'filetype', test_state.original_filetype)
    end
    
    -- Close test buffer
    if test_state.test_buffer and vim.api.nvim_buf_is_valid(test_state.test_buffer) then
        pcall(vim.api.nvim_buf_delete, test_state.test_buffer, { force = true })
    end
    
    -- Clean up test directory
    if test_state.temp_directory and vim.fn.isdirectory(test_state.temp_directory) == 1 then
        vim.fn.delete(test_state.temp_directory, "rf")
        test_state.temp_directory = nil
    end
    
    test_state.test_buffer = nil
    test_state.original_filetype = nil
end

-- Create test buffer with specific filetype
local function create_test_buffer(filetype, content)
    local buf = vim.api.nvim_create_buf(false, true)
    test_state.test_buffer = buf
    
    if content then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
    end
    
    vim.api.nvim_buf_set_option(buf, 'filetype', filetype)
    vim.api.nvim_set_current_buf(buf)
    
    return buf
end

-- nvim-cmp Compatibility Tests
local function test_nvim_cmp_compatibility()
    test_state.current_test = "nvim_cmp_compatibility"
    
    local cmp_available = pcall(require, "cmp")
    
    if not cmp_available then
        test_state.results.nvim_cmp_compatibility = {
            passed = true, -- Pass if nvim-cmp not available (optional)
            available = false,
            message = "nvim-cmp not available - skipping test"
        }
        return true
    end
    
    local cmp = require("cmp")
    local completion_manager = require("pebble.completion.manager")
    
    -- Test source registration
    local registration_success = false
    local registration_error = nil
    
    local success, result = pcall(function()
        return completion_manager.register_nvim_cmp({
            priority = 100,
            max_item_count = 50,
            trigger_characters = { "[", "(" }
        })
    end)
    
    if success then
        registration_success = result
    else
        registration_error = result
    end
    
    -- Test source functionality if registration succeeded
    local source_functionality = false
    local source_error = nil
    
    if registration_success then
        -- Create markdown buffer for testing
        local buf = create_test_buffer("markdown", {"This is a test [[completion"})
        
        -- Position cursor at end of completion trigger
        vim.api.nvim_win_set_cursor(0, {1, 25}) -- After "[[completion"
        
        -- Try to get completions through nvim-cmp source
        local pebble_source = nil
        for _, source in pairs(cmp.core.sources) do
            if source.name == "pebble" then
                pebble_source = source
                break
            end
        end
        
        if pebble_source then
            local success_comp, result_comp = pcall(function()
                local request = {
                    context = {
                        cursor_line = vim.api.nvim_get_current_line(),
                        cursor = vim.api.nvim_win_get_cursor(0)
                    }
                }
                
                local items = nil
                pebble_source.source:complete(request, function(response)
                    items = response.items or {}
                end)
                
                -- Wait briefly for async completion
                vim.wait(100)
                return items
            end)
            
            if success_comp and result_comp then
                source_functionality = true
            else
                source_error = result_comp or "Failed to get completions"
            end
        else
            source_error = "Pebble source not found in nvim-cmp sources"
        end
    end
    
    local passed = registration_success and source_functionality
    
    test_state.results.nvim_cmp_compatibility = {
        passed = passed,
        available = cmp_available,
        registration_success = registration_success,
        registration_error = registration_error,
        source_functionality = source_functionality,
        source_error = source_error
    }
    
    return passed
end

-- blink.cmp Compatibility Tests
local function test_blink_cmp_compatibility()
    test_state.current_test = "blink_cmp_compatibility"
    
    local blink_available = pcall(require, "blink.cmp")
    
    if not blink_available then
        test_state.results.blink_cmp_compatibility = {
            passed = true, -- Pass if blink.cmp not available (optional)
            available = false,
            message = "blink.cmp not available - skipping test"
        }
        return true
    end
    
    local completion_manager = require("pebble.completion.manager")
    
    -- Test source registration
    local registration_success = false
    local registration_error = nil
    
    local success, result = pcall(function()
        return completion_manager.register_blink_cmp({
            priority = 100,
            max_item_count = 50,
            trigger_characters = { "[", "(" }
        })
    end)
    
    if success then
        registration_success = result
    else
        registration_error = result
    end
    
    -- Note: Testing actual blink.cmp functionality would require more complex setup
    -- For now, we just test registration
    
    test_state.results.blink_cmp_compatibility = {
        passed = registration_success,
        available = blink_available,
        registration_success = registration_success,
        registration_error = registration_error
    }
    
    return registration_success
end

-- Multiple Source Interaction Tests
local function test_multiple_source_interaction()
    test_state.current_test = "multiple_source_interaction"
    
    local completion_manager = require("pebble.completion.manager")
    
    -- Initialize manager with multiple sources
    local manager_setup_success = false
    local setup_error = nil
    
    local success, result = pcall(function()
        completion_manager.setup({
            nvim_cmp = { enabled = true },
            blink_cmp = { enabled = true },
            debug = true
        })
        return completion_manager.register_all_sources()
    end)
    
    if success then
        manager_setup_success = result
    else
        setup_error = result
    end
    
    -- Test manager status
    local status = completion_manager.get_status()
    local status_valid = status and 
                        status.initialized and 
                        type(status.registered_sources) == "table" and
                        type(status.completion_stats) == "table"
    
    -- Test cache operations
    local cache_operations_success = false
    local cache_error = nil
    
    local success_cache, result_cache = pcall(function()
        completion_manager.refresh_cache()
        return true
    end)
    
    if success_cache then
        cache_operations_success = result_cache
    else
        cache_error = result_cache
    end
    
    local passed = manager_setup_success and status_valid and cache_operations_success
    
    test_state.results.multiple_source_interaction = {
        passed = passed,
        manager_setup_success = manager_setup_success,
        setup_error = setup_error,
        status_valid = status_valid,
        status = status,
        cache_operations_success = cache_operations_success,
        cache_error = cache_error
    }
    
    return passed
end

-- Filetype Switching Tests
local function test_filetype_switching()
    test_state.current_test = "filetype_switching"
    
    local completion = require("pebble.completion")
    
    -- Test completion enabled/disabled based on filetype
    local filetype_tests = {
        { filetype = "markdown", should_be_enabled = true },
        { filetype = "text", should_be_enabled = false },
        { filetype = "lua", should_be_enabled = false },
        { filetype = "python", should_be_enabled = false }
    }
    
    local passed_tests = 0
    local filetype_results = {}
    
    for _, test_case in ipairs(filetype_tests) do
        -- Create buffer with specific filetype
        local buf = create_test_buffer(test_case.filetype, {"Test content [[link"})
        
        -- Test if completion is enabled for this filetype
        local is_enabled = completion.is_completion_enabled()
        local correct = is_enabled == test_case.should_be_enabled
        
        filetype_results[test_case.filetype] = {
            expected_enabled = test_case.should_be_enabled,
            actually_enabled = is_enabled,
            correct = correct
        }
        
        if correct then
            passed_tests = passed_tests + 1
        end
        
        -- Clean up buffer
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
    
    local all_passed = passed_tests == #filetype_tests
    
    test_state.results.filetype_switching = {
        passed = all_passed,
        passed_count = passed_tests,
        total_count = #filetype_tests,
        filetype_results = filetype_results
    }
    
    return all_passed
end

-- Error Recovery Tests
local function test_error_recovery()
    test_state.current_test = "error_recovery"
    
    local completion = require("pebble.completion")
    
    -- Test recovery from various error conditions
    local error_tests = {}
    
    -- Test 1: Invalid directory
    local test1_success = false
    local test1_error = nil
    
    local success1, result1 = pcall(function()
        local results = completion.get_wiki_completions("test", "/nonexistent/directory")
        return #results == 0  -- Should return empty results, not crash
    end)
    
    if success1 then
        test1_success = result1
    else
        test1_error = result1
    end
    
    error_tests.invalid_directory = {
        success = test1_success,
        error = test1_error
    }
    
    -- Test 2: Invalid query parameters
    local test2_success = false
    local test2_error = nil
    
    local success2, result2 = pcall(function()
        local results = completion.get_wiki_completions(nil, test_state.temp_directory)
        return type(results) == "table"  -- Should return table, not crash
    end)
    
    if success2 then
        test2_success = result2
    else
        test2_error = result2
    end
    
    error_tests.invalid_query = {
        success = test2_success,
        error = test2_error
    }
    
    -- Test 3: Malformed files
    local malformed_file = test_state.temp_directory .. "/malformed.md"
    vim.fn.writefile({"This is not valid YAML", "frontmatter", "---"}, malformed_file)
    
    local test3_success = false
    local test3_error = nil
    
    local success3, result3 = pcall(function()
        completion.invalidate_cache()  -- Force cache rebuild
        local results = completion.get_wiki_completions("test", test_state.temp_directory)
        return type(results) == "table"  -- Should handle malformed files gracefully
    end)
    
    if success3 then
        test3_success = result3
    else
        test3_error = result3
    end
    
    error_tests.malformed_files = {
        success = test3_success,
        error = test3_error
    }
    
    -- Test 4: Context detection with invalid cursor position
    local original_get_cursor = vim.api.nvim_win_get_cursor
    
    local test4_success = false
    local test4_error = nil
    
    vim.api.nvim_win_get_cursor = function() error("Mock cursor error") end
    
    local success4, result4 = pcall(function()
        local is_wiki, query = completion.is_wiki_link_context()
        return is_wiki == false and query == ""  -- Should handle error gracefully
    end)
    
    vim.api.nvim_win_get_cursor = original_get_cursor  -- Restore
    
    if success4 then
        test4_success = result4
    else
        test4_error = result4
    end
    
    error_tests.invalid_cursor = {
        success = test4_success,
        error = test4_error
    }
    
    -- Count passed tests
    local passed_count = 0
    for _, test_result in pairs(error_tests) do
        if test_result.success then
            passed_count = passed_count + 1
        end
    end
    
    local all_passed = passed_count == vim.tbl_count(error_tests)
    
    test_state.results.error_recovery = {
        passed = all_passed,
        passed_count = passed_count,
        total_count = vim.tbl_count(error_tests),
        error_tests = error_tests
    }
    
    return all_passed
end

-- Performance Under Load Tests
local function test_performance_under_load()
    test_state.current_test = "performance_under_load"
    
    local completion = require("pebble.completion")
    
    -- Create many test files
    local load_dir = test_state.temp_directory .. "/load_test"
    vim.fn.mkdir(load_dir, "p")
    
    local file_count = 50
    for i = 1, file_count do
        local filepath = load_dir .. "/load-file-" .. i .. ".md"
        local content = {
            "---",
            "title: Load File " .. i,
            "aliases: [\"load-" .. i .. "\", \"file-" .. i .. "\"]",
            "tags: [\"load\", \"test\", \"file-" .. i .. "\"]",
            "---",
            "",
            "# Load File " .. i,
            "",
            "This is load test file [[load-file-" .. (i + 1) .. "]].",
            "",
            "#load-test-" .. i
        }
        vim.fn.writefile(content, filepath)
    end
    
    -- Test performance with many files
    local start_time = vim.loop.hrtime()
    
    local success, result = pcall(function()
        completion.invalidate_cache()  -- Force rebuild
        local results = completion.get_wiki_completions("load", load_dir)
        return #results
    end)
    
    local end_time = vim.loop.hrtime()
    local duration_ms = (end_time - start_time) / 1000000
    
    local passed = success and result > 0 and duration_ms < 2000  -- Should complete within 2 seconds
    
    test_state.results.performance_under_load = {
        passed = passed,
        success = success,
        result_count = success and result or 0,
        duration_ms = duration_ms,
        file_count = file_count,
        error = success and nil or result
    }
    
    -- Clean up load test files
    vim.fn.delete(load_dir, "rf")
    
    return passed
end

-- Main integration test runner
function M.run_integration_tests()
    log_info("Starting integration testing framework")
    
    local test_dir = setup_integration_test_env()
    if not test_dir then
        log_error("Failed to setup integration test environment")
        return false
    end
    
    local tests = {
        test_nvim_cmp_compatibility,
        test_blink_cmp_compatibility,
        test_multiple_source_interaction,
        test_filetype_switching,
        test_error_recovery,
        test_performance_under_load
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
    
    cleanup_integration_test_env()
    
    local all_passed = passed_count == total_count
    log_info("Integration testing completed: " .. passed_count .. "/" .. total_count .. " tests passed")
    
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
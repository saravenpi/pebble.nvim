-- Pebble Testing Framework
-- Comprehensive testing and validation for the completion system
local M = {}

-- Test configuration
local TEST_CONFIG = {
    -- Safety limits for stress testing
    max_files = 1000,
    max_cache_size = 2000,
    timeout_ms = 5000,
    memory_threshold_mb = 100,
    
    -- Performance benchmarks
    completion_time_threshold_ms = 200,
    cache_build_time_threshold_ms = 1000,
    
    -- Test data
    test_directory = vim.fn.tempname() .. "_pebble_tests",
    
    -- Debug mode
    debug = false,
}

-- Test state
local test_state = {
    current_test = nil,
    test_results = {},
    performance_metrics = {},
    error_log = {},
    memory_usage = {},
}

-- Logging utilities
local function log_debug(msg)
    if TEST_CONFIG.debug then
        print("[PEBBLE TEST DEBUG] " .. msg)
    end
end

local function log_info(msg)
    print("[PEBBLE TEST] " .. msg)
end

local function log_error(msg)
    local error_entry = {
        timestamp = os.time(),
        message = msg,
        test = test_state.current_test
    }
    table.insert(test_state.error_log, error_entry)
    print("[PEBBLE TEST ERROR] " .. msg)
end

-- Performance monitoring utilities
local function start_performance_timer(operation)
    local start_time = vim.loop.hrtime()
    return function()
        local end_time = vim.loop.hrtime()
        local duration_ms = (end_time - start_time) / 1000000
        
        if not test_state.performance_metrics[operation] then
            test_state.performance_metrics[operation] = {}
        end
        
        table.insert(test_state.performance_metrics[operation], duration_ms)
        return duration_ms
    end
end

local function measure_memory_usage()
    -- Get memory usage in MB (approximation using collectgarbage)
    local kb_before = collectgarbage("count")
    collectgarbage("collect")
    local kb_after = collectgarbage("count")
    
    local memory_freed = kb_before - kb_after
    local current_memory = kb_after / 1024  -- Convert to MB
    
    table.insert(test_state.memory_usage, {
        timestamp = os.time(),
        memory_mb = current_memory,
        freed_kb = memory_freed
    })
    
    return current_memory
end

-- Test environment setup
local function setup_test_environment()
    log_debug("Setting up test environment")
    
    -- Create test directory
    if vim.fn.isdirectory(TEST_CONFIG.test_directory) == 0 then
        vim.fn.mkdir(TEST_CONFIG.test_directory, "p")
    end
    
    -- Create test markdown files
    local test_files = {
        "test-note-1.md",
        "test-note-2.md",
        "folder/nested-note.md",
        "special characters & symbols.md",
        "long-filename-with-many-words-to-test-completion.md"
    }
    
    for _, filename in ipairs(test_files) do
        local filepath = TEST_CONFIG.test_directory .. "/" .. filename
        local dir = vim.fn.fnamemodify(filepath, ":h")
        
        if vim.fn.isdirectory(dir) == 0 then
            vim.fn.mkdir(dir, "p")
        end
        
        -- Create file with YAML frontmatter and content
        local title = vim.fn.fnamemodify(filename, ":t:r"):gsub("-", " "):gsub("_", " ")
        local content = {
            "---",
            "title: " .. title,
            "aliases: [\"" .. title:lower() .. "\", \"test-alias-" .. string.sub(filename, 1, 5) .. "\"]",
            "tags: [\"test\", \"completion\"]",
            "---",
            "",
            "# " .. title,
            "",
            "This is a test note for [[completion testing]].",
            "",
            "Link to [another file](test-note-2.md).",
            "",
            "#test-tag #completion-tag"
        }
        
        vim.fn.writefile(content, filepath)
    end
    
    log_info("Test environment created with " .. #test_files .. " test files")
    return true
end

local function cleanup_test_environment()
    log_debug("Cleaning up test environment")
    
    if vim.fn.isdirectory(TEST_CONFIG.test_directory) == 1 then
        vim.fn.delete(TEST_CONFIG.test_directory, "rf")
    end
    
    log_info("Test environment cleaned up")
end

-- Safety validation tests
local function test_stress_large_repository()
    test_state.current_test = "stress_large_repository"
    log_info("Running stress test with large repository simulation")
    
    local stop_timer = start_performance_timer("stress_test")
    local initial_memory = measure_memory_usage()
    
    -- Create many test files to simulate large repository
    local stress_dir = TEST_CONFIG.test_directory .. "/stress"
    vim.fn.mkdir(stress_dir, "p")
    
    local file_count = math.min(TEST_CONFIG.max_files, 200)  -- Reasonable limit for testing
    
    for i = 1, file_count do
        local filepath = stress_dir .. "/stress-file-" .. i .. ".md"
        local content = {
            "---",
            "title: Stress File " .. i,
            "---",
            "",
            "# Stress File " .. i,
            "",
            "This is stress test file number " .. i,
            "",
            "Links: [[stress-file-" .. (i + 1) .. "]] [[stress-file-" .. (i - 1) .. "]]"
        }
        
        vim.fn.writefile(content, filepath)
    end
    
    -- Test completion system under stress
    local completion = require("pebble.completion")
    
    -- Clear cache to force rebuilding
    completion.invalidate_cache()
    
    -- Test completion performance
    local success, result = pcall(function()
        local notes = completion.get_wiki_completions("stress", stress_dir)
        return #notes
    end)
    
    local duration_ms = stop_timer()
    local final_memory = measure_memory_usage()
    local memory_used = final_memory - initial_memory
    
    -- Evaluate results
    local passed = true
    local issues = {}
    
    if not success then
        passed = false
        table.insert(issues, "Completion failed under stress: " .. (result or "unknown error"))
    end
    
    if duration_ms > TEST_CONFIG.completion_time_threshold_ms * 5 then  -- Allow 5x normal time for stress test
        passed = false
        table.insert(issues, "Completion too slow under stress: " .. duration_ms .. "ms")
    end
    
    if memory_used > TEST_CONFIG.memory_threshold_mb then
        passed = false
        table.insert(issues, "Excessive memory usage: " .. memory_used .. "MB")
    end
    
    test_state.test_results.stress_large_repository = {
        passed = passed,
        duration_ms = duration_ms,
        memory_used_mb = memory_used,
        files_processed = success and result or 0,
        issues = issues
    }
    
    -- Cleanup stress files
    vim.fn.delete(stress_dir, "rf")
    
    log_info("Stress test completed: " .. (passed and "PASSED" or "FAILED"))
    return passed
end

local function test_memory_leak_detection()
    test_state.current_test = "memory_leak_detection"
    log_info("Running memory leak detection test")
    
    local completion = require("pebble.completion")
    local initial_memory = measure_memory_usage()
    
    -- Perform repeated operations that could cause memory leaks
    local iterations = 50
    local memory_samples = {}
    
    for i = 1, iterations do
        -- Clear and rebuild cache multiple times
        completion.invalidate_cache()
        
        local notes = completion.get_wiki_completions("test", TEST_CONFIG.test_directory)
        
        -- Force garbage collection and measure memory
        collectgarbage("collect")
        local current_memory = measure_memory_usage()
        table.insert(memory_samples, current_memory)
        
        -- Brief pause to allow system cleanup
        vim.wait(10)
    end
    
    -- Analyze memory trend
    local memory_trend_positive = 0
    for i = 2, #memory_samples do
        if memory_samples[i] > memory_samples[i-1] then
            memory_trend_positive = memory_trend_positive + 1
        end
    end
    
    local final_memory = measure_memory_usage()
    local memory_growth = final_memory - initial_memory
    local leak_detected = memory_growth > 10  -- 10MB growth threshold
    
    test_state.test_results.memory_leak_detection = {
        passed = not leak_detected,
        iterations = iterations,
        initial_memory_mb = initial_memory,
        final_memory_mb = final_memory,
        memory_growth_mb = memory_growth,
        trend_positive_percent = (memory_trend_positive / iterations) * 100,
        leak_detected = leak_detected
    }
    
    log_info("Memory leak test completed: " .. (not leak_detected and "PASSED" or "FAILED"))
    return not leak_detected
end

local function test_timeout_handling()
    test_state.current_test = "timeout_handling"
    log_info("Running timeout handling test")
    
    local completion = require("pebble.completion")
    local passed = true
    local issues = {}
    
    -- Test completion with timeout
    local function test_with_timeout(operation_name, operation, timeout_ms)
        local timed_out = false
        local result = nil
        local error_msg = nil
        
        local timer = vim.loop.new_timer()
        timer:start(timeout_ms, 0, function()
            timed_out = true
        end)
        
        local success, res = pcall(operation)
        timer:close()
        
        if timed_out then
            return false, "Operation timed out after " .. timeout_ms .. "ms"
        elseif not success then
            return false, "Operation failed: " .. (res or "unknown error")
        else
            return true, res
        end
    end
    
    -- Test various operations with timeouts
    local operations = {
        {
            name = "wiki_completion",
            operation = function()
                return completion.get_wiki_completions("test", TEST_CONFIG.test_directory)
            end,
            timeout = TEST_CONFIG.timeout_ms
        },
        {
            name = "markdown_completion", 
            operation = function()
                return completion.get_markdown_link_completions("test", TEST_CONFIG.test_directory)
            end,
            timeout = TEST_CONFIG.timeout_ms
        },
        {
            name = "cache_invalidation",
            operation = function()
                completion.invalidate_cache()
                return true
            end,
            timeout = 1000
        }
    }
    
    local results = {}
    
    for _, op in ipairs(operations) do
        local success, result = test_with_timeout(op.name, op.operation, op.timeout)
        results[op.name] = {
            success = success,
            result = success and "OK" or result
        }
        
        if not success then
            passed = false
            table.insert(issues, op.name .. ": " .. result)
        end
    end
    
    test_state.test_results.timeout_handling = {
        passed = passed,
        operations = results,
        issues = issues
    }
    
    log_info("Timeout handling test completed: " .. (passed and "PASSED" or "FAILED"))
    return passed
end

-- Performance profiling
local function test_performance_profiling()
    test_state.current_test = "performance_profiling"
    log_info("Running performance profiling test")
    
    local completion = require("pebble.completion")
    local profile_results = {}
    
    -- Profile different operations
    local operations = {
        {
            name = "cache_build",
            operation = function()
                completion.invalidate_cache()
                return completion.get_wiki_completions("", TEST_CONFIG.test_directory)
            end,
            threshold = TEST_CONFIG.cache_build_time_threshold_ms
        },
        {
            name = "wiki_completion_empty",
            operation = function()
                return completion.get_wiki_completions("", TEST_CONFIG.test_directory)
            end,
            threshold = TEST_CONFIG.completion_time_threshold_ms
        },
        {
            name = "wiki_completion_partial",
            operation = function()
                return completion.get_wiki_completions("test", TEST_CONFIG.test_directory)
            end,
            threshold = TEST_CONFIG.completion_time_threshold_ms
        },
        {
            name = "fuzzy_matching",
            operation = function()
                return completion.get_wiki_completions("tst", TEST_CONFIG.test_directory)
            end,
            threshold = TEST_CONFIG.completion_time_threshold_ms
        }
    }
    
    local passed = true
    
    for _, op in ipairs(operations) do
        local times = {}
        local runs = 5
        
        for i = 1, runs do
            local stop_timer = start_performance_timer(op.name)
            local success, result = pcall(op.operation)
            local duration = stop_timer()
            
            if success then
                table.insert(times, duration)
            else
                passed = false
                log_error("Performance test failed for " .. op.name .. ": " .. (result or "unknown"))
            end
        end
        
        if #times > 0 then
            local avg_time = 0
            local max_time = 0
            local min_time = math.huge
            
            for _, time in ipairs(times) do
                avg_time = avg_time + time
                max_time = math.max(max_time, time)
                min_time = math.min(min_time, time)
            end
            
            avg_time = avg_time / #times
            
            local performance_ok = avg_time <= op.threshold
            
            profile_results[op.name] = {
                avg_time_ms = avg_time,
                max_time_ms = max_time,
                min_time_ms = min_time,
                runs = runs,
                threshold_ms = op.threshold,
                performance_ok = performance_ok
            }
            
            if not performance_ok then
                passed = false
            end
        end
    end
    
    test_state.test_results.performance_profiling = {
        passed = passed,
        profiles = profile_results
    }
    
    log_info("Performance profiling completed: " .. (passed and "PASSED" or "FAILED"))
    return passed
end

-- Main test runner for safety validation
function M.run_safety_tests()
    log_info("Starting safety validation tests")
    
    local setup_success = setup_test_environment()
    if not setup_success then
        log_error("Failed to setup test environment")
        return false
    end
    
    local tests = {
        test_stress_large_repository,
        test_memory_leak_detection,
        test_timeout_handling,
        test_performance_profiling
    }
    
    local passed_count = 0
    local total_count = #tests
    
    for _, test_func in ipairs(tests) do
        local success, result = pcall(test_func)
        if success and result then
            passed_count = passed_count + 1
        elseif not success then
            log_error("Test crashed: " .. (result or "unknown error"))
        end
    end
    
    cleanup_test_environment()
    
    local all_passed = passed_count == total_count
    log_info("Safety validation completed: " .. passed_count .. "/" .. total_count .. " tests passed")
    
    return all_passed, {
        passed = passed_count,
        total = total_count,
        results = test_state.test_results,
        performance_metrics = test_state.performance_metrics,
        error_log = test_state.error_log,
        memory_usage = test_state.memory_usage
    }
end

-- Test configuration
function M.configure(opts)
    TEST_CONFIG = vim.tbl_deep_extend("force", TEST_CONFIG, opts or {})
end

-- Get test results
function M.get_results()
    return {
        test_results = test_state.test_results,
        performance_metrics = test_state.performance_metrics,
        error_log = test_state.error_log,
        memory_usage = test_state.memory_usage
    }
end

return M
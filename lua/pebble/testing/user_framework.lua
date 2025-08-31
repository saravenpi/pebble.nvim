-- User Testing Framework
-- Simple test commands, validation scripts, performance benchmarks, and error reproduction tools
local M = {}

-- Framework state
local framework_state = {
    current_benchmark = nil,
    test_results = {},
    user_reports = {},
    config = {
        benchmark_iterations = 10,
        timeout_ms = 5000,
        verbose = false,
    }
}

-- Logging utilities
local function log_info(msg, force)
    if framework_state.config.verbose or force then
        print("[PEBBLE USER TEST] " .. msg)
    end
end

local function log_error(msg)
    print("[PEBBLE USER TEST ERROR] " .. msg)
end

local function log_success(msg)
    print("[PEBBLE USER TEST SUCCESS] " .. msg)
end

-- Simple validation script
function M.validate_completion_setup()
    log_info("Validating Pebble completion setup...", true)
    
    local validation_results = {
        timestamp = os.time(),
        checks = {},
        overall_status = "unknown",
        issues = {},
        recommendations = {}
    }
    
    -- Check 1: Core modules available
    local core_modules = {
        "pebble.completion",
        "pebble.completion.manager", 
        "pebble.bases.search"
    }
    
    for _, module_name in ipairs(core_modules) do
        local success, module = pcall(require, module_name)
        local check_result = {
            name = "module_" .. module_name:gsub("%.", "_"),
            status = success and "pass" or "fail",
            message = success and "Module loaded successfully" or "Failed to load module",
            error = success and nil or module
        }
        
        table.insert(validation_results.checks, check_result)
        
        if not success then
            table.insert(validation_results.issues, "Missing module: " .. module_name)
            table.insert(validation_results.recommendations, "Ensure Pebble is properly installed")
        end
    end
    
    -- Check 2: Completion manager initialization
    local success, completion_manager = pcall(require, "pebble.completion.manager")
    if success then
        local manager_status = completion_manager.get_status()
        local check_result = {
            name = "completion_manager_status",
            status = manager_status and manager_status.initialized and "pass" or "fail",
            message = manager_status and manager_status.initialized and 
                     "Manager initialized with " .. vim.tbl_count(manager_status.registered_sources) .. " sources" or
                     "Manager not properly initialized",
            data = manager_status
        }
        
        table.insert(validation_results.checks, check_result)
        
        if not (manager_status and manager_status.initialized) then
            table.insert(validation_results.issues, "Completion manager not initialized")
            table.insert(validation_results.recommendations, "Call require('pebble').setup() in your config")
        end
        
        -- Check for available completion engines
        if manager_status and manager_status.available_engines then
            local engine_count = 0
            for engine, available in pairs(manager_status.available_engines) do
                if available then
                    engine_count = engine_count + 1
                    log_info("✓ " .. engine .. " is available")
                else
                    log_info("✗ " .. engine .. " is not available")
                end
            end
            
            if engine_count == 0 then
                table.insert(validation_results.issues, "No completion engines available")
                table.insert(validation_results.recommendations, "Install nvim-cmp or blink.cmp for completion")
            end
        end
    end
    
    -- Check 3: File system setup
    local completion = require("pebble.completion")
    local root_dir = completion.get_root_dir()
    
    local fs_check = {
        name = "file_system_setup",
        status = "unknown",
        message = "",
        data = { root_dir = root_dir }
    }
    
    if not root_dir then
        fs_check.status = "fail"
        fs_check.message = "Cannot determine root directory"
        table.insert(validation_results.issues, "No root directory found")
        table.insert(validation_results.recommendations, "Navigate to a git repository or set working directory")
    elseif vim.fn.isdirectory(root_dir) == 0 then
        fs_check.status = "fail"
        fs_check.message = "Root directory does not exist: " .. root_dir
        table.insert(validation_results.issues, "Root directory invalid")
    else
        -- Check for markdown files
        local search = require("pebble.bases.search")
        local md_files = search.find_markdown_files_sync(root_dir)
        
        fs_check.status = #md_files > 0 and "pass" or "warning"
        fs_check.message = "Root directory: " .. root_dir .. " (" .. #md_files .. " markdown files)"
        fs_check.data.markdown_file_count = #md_files
        
        if #md_files == 0 then
            table.insert(validation_results.issues, "No markdown files found in " .. root_dir)
            table.insert(validation_results.recommendations, "Create some .md files to test completion")
        end
    end
    
    table.insert(validation_results.checks, fs_check)
    
    -- Check 4: Basic completion functionality
    if root_dir and vim.fn.isdirectory(root_dir) == 1 then
        local completion_test = {
            name = "basic_completion_test",
            status = "unknown",
            message = "",
            data = {}
        }
        
        local test_success, test_result = pcall(function()
            local completions = completion.get_wiki_completions("", root_dir)
            return completions
        end)
        
        if test_success and type(test_result) == "table" then
            completion_test.status = #test_result > 0 and "pass" or "warning"
            completion_test.message = "Found " .. #test_result .. " completion items"
            completion_test.data.completion_count = #test_result
            
            if #test_result == 0 then
                table.insert(validation_results.recommendations, "Add more markdown files with frontmatter to improve completions")
            end
        else
            completion_test.status = "fail"
            completion_test.message = "Completion test failed: " .. (test_result or "unknown error")
            table.insert(validation_results.issues, "Basic completion functionality broken")
        end
        
        table.insert(validation_results.checks, completion_test)
    end
    
    -- Determine overall status
    local pass_count = 0
    local fail_count = 0
    local warning_count = 0
    
    for _, check in ipairs(validation_results.checks) do
        if check.status == "pass" then
            pass_count = pass_count + 1
        elseif check.status == "fail" then
            fail_count = fail_count + 1
        elseif check.status == "warning" then
            warning_count = warning_count + 1
        end
    end
    
    if fail_count > 0 then
        validation_results.overall_status = "failed"
    elseif warning_count > 0 then
        validation_results.overall_status = "warnings"
    else
        validation_results.overall_status = "passed"
    end
    
    -- Report results
    log_info("=== Validation Results ===", true)
    log_info("Overall Status: " .. validation_results.overall_status:upper(), true)
    log_info("Checks: " .. pass_count .. " passed, " .. warning_count .. " warnings, " .. fail_count .. " failed", true)
    
    if #validation_results.issues > 0 then
        log_info("\nIssues found:", true)
        for _, issue in ipairs(validation_results.issues) do
            log_info("  - " .. issue, true)
        end
    end
    
    if #validation_results.recommendations > 0 then
        log_info("\nRecommendations:", true)
        for _, rec in ipairs(validation_results.recommendations) do
            log_info("  - " .. rec, true)
        end
    end
    
    log_info("=== End Validation ===", true)
    
    framework_state.test_results.validation = validation_results
    return validation_results
end

-- Performance benchmark
function M.run_performance_benchmark()
    log_info("Running performance benchmark...", true)
    
    local benchmark_results = {
        timestamp = os.time(),
        iterations = framework_state.config.benchmark_iterations,
        operations = {},
        summary = {}
    }
    
    local completion = require("pebble.completion")
    local root_dir = completion.get_root_dir()
    
    if not root_dir or vim.fn.isdirectory(root_dir) == 0 then
        log_error("Cannot run benchmark: invalid root directory")
        return nil
    end
    
    -- Benchmark operations
    local operations = {
        {
            name = "cache_invalidation",
            description = "Cache invalidation",
            operation = function()
                completion.invalidate_cache()
            end
        },
        {
            name = "wiki_completion_empty",
            description = "Wiki completion (empty query)", 
            operation = function()
                return completion.get_wiki_completions("", root_dir)
            end
        },
        {
            name = "wiki_completion_partial",
            description = "Wiki completion (partial query)",
            operation = function()
                return completion.get_wiki_completions("test", root_dir)
            end
        },
        {
            name = "markdown_completion",
            description = "Markdown link completion",
            operation = function()
                return completion.get_markdown_link_completions("test", root_dir)
            end
        },
        {
            name = "context_detection_wiki",
            description = "Wiki context detection",
            operation = function()
                -- Mock context for testing
                local orig_get_line = vim.api.nvim_get_current_line
                local orig_get_cursor = vim.api.nvim_win_get_cursor
                
                vim.api.nvim_get_current_line = function() return "This is [[test" end
                vim.api.nvim_win_get_cursor = function() return {1, 12} end
                
                local is_wiki, query = completion.is_wiki_link_context()
                
                -- Restore
                vim.api.nvim_get_current_line = orig_get_line
                vim.api.nvim_win_get_cursor = orig_get_cursor
                
                return { is_wiki = is_wiki, query = query }
            end
        }
    }
    
    framework_state.current_benchmark = "performance"
    
    for _, op_info in ipairs(operations) do
        log_info("Benchmarking: " .. op_info.description)
        
        local operation_results = {
            name = op_info.name,
            description = op_info.description,
            times = {},
            errors = {},
            statistics = {}
        }
        
        for i = 1, benchmark_results.iterations do
            local start_time = vim.loop.hrtime()
            
            local success, result = pcall(op_info.operation)
            
            local end_time = vim.loop.hrtime()
            local duration_ms = (end_time - start_time) / 1000000
            
            if success then
                table.insert(operation_results.times, duration_ms)
            else
                table.insert(operation_results.errors, { iteration = i, error = result })
                log_error("Benchmark error in " .. op_info.name .. " iteration " .. i .. ": " .. (result or "unknown"))
            end
        end
        
        -- Calculate statistics
        if #operation_results.times > 0 then
            local total = 0
            local min_time = math.huge
            local max_time = 0
            
            for _, time in ipairs(operation_results.times) do
                total = total + time
                min_time = math.min(min_time, time)
                max_time = math.max(max_time, time)
            end
            
            operation_results.statistics = {
                avg_ms = total / #operation_results.times,
                min_ms = min_time,
                max_ms = max_time,
                successful_runs = #operation_results.times,
                error_count = #operation_results.errors
            }
        else
            operation_results.statistics = {
                avg_ms = 0,
                min_ms = 0,
                max_ms = 0,
                successful_runs = 0,
                error_count = #operation_results.errors
            }
        end
        
        benchmark_results.operations[op_info.name] = operation_results
        
        -- Log results for this operation
        if operation_results.statistics.successful_runs > 0 then
            log_info(string.format("  ✓ %s: %.2fms avg (%.2f-%.2fms range)", 
                     op_info.description,
                     operation_results.statistics.avg_ms,
                     operation_results.statistics.min_ms,
                     operation_results.statistics.max_ms))
        else
            log_error("  ✗ " .. op_info.description .. ": All runs failed")
        end
    end
    
    -- Generate summary
    local total_operations = 0
    local successful_operations = 0
    local avg_performance = 0
    
    for _, op_result in pairs(benchmark_results.operations) do
        total_operations = total_operations + 1
        if op_result.statistics.successful_runs > 0 then
            successful_operations = successful_operations + 1
            avg_performance = avg_performance + op_result.statistics.avg_ms
        end
    end
    
    benchmark_results.summary = {
        total_operations = total_operations,
        successful_operations = successful_operations,
        avg_performance_ms = successful_operations > 0 and (avg_performance / successful_operations) or 0,
        success_rate = (successful_operations / total_operations) * 100
    }
    
    log_info("=== Benchmark Results ===", true)
    log_info(string.format("Success Rate: %.1f%% (%d/%d operations)", 
             benchmark_results.summary.success_rate,
             successful_operations,
             total_operations), true)
    log_info(string.format("Average Performance: %.2fms", benchmark_results.summary.avg_performance_ms), true)
    log_info("=== End Benchmark ===", true)
    
    framework_state.current_benchmark = nil
    framework_state.test_results.performance_benchmark = benchmark_results
    
    return benchmark_results
end

-- Error reproduction tool
function M.reproduce_common_errors()
    log_info("Testing common error scenarios...", true)
    
    local error_tests = {
        timestamp = os.time(),
        tests = {},
        summary = { passed = 0, failed = 0, errors = 0 }
    }
    
    local test_scenarios = {
        {
            name = "invalid_root_directory",
            description = "Completion with invalid root directory",
            test = function()
                local completion = require("pebble.completion")
                local results = completion.get_wiki_completions("test", "/nonexistent/path")
                return type(results) == "table" and #results == 0
            end,
            expected_behavior = "Should return empty table without crashing"
        },
        {
            name = "nil_query",
            description = "Completion with nil query",
            test = function()
                local completion = require("pebble.completion")
                local root_dir = completion.get_root_dir()
                local results = completion.get_wiki_completions(nil, root_dir)
                return type(results) == "table"
            end,
            expected_behavior = "Should handle nil query gracefully"
        },
        {
            name = "invalid_cursor_position",
            description = "Context detection with invalid cursor",
            test = function()
                local completion = require("pebble.completion")
                
                -- Mock invalid cursor position
                local orig_get_cursor = vim.api.nvim_win_get_cursor
                vim.api.nvim_win_get_cursor = function() error("Invalid cursor") end
                
                local success, is_wiki, query = pcall(completion.is_wiki_link_context)
                
                -- Restore
                vim.api.nvim_win_get_cursor = orig_get_cursor
                
                return success and is_wiki == false and query == ""
            end,
            expected_behavior = "Should handle cursor errors gracefully"
        },
        {
            name = "cache_stress_test",
            description = "Rapid cache invalidation and rebuild",
            test = function()
                local completion = require("pebble.completion")
                local root_dir = completion.get_root_dir()
                
                -- Rapidly invalidate and use cache multiple times
                for i = 1, 10 do
                    completion.invalidate_cache()
                    local results = completion.get_wiki_completions("", root_dir)
                    if type(results) ~= "table" then
                        return false
                    end
                end
                return true
            end,
            expected_behavior = "Should handle rapid cache operations"
        }
    }
    
    for _, scenario in ipairs(test_scenarios) do
        log_info("Testing: " .. scenario.description)
        
        local test_result = {
            name = scenario.name,
            description = scenario.description,
            expected = scenario.expected_behavior,
            status = "unknown",
            error = nil,
            passed = false
        }
        
        local success, result = pcall(scenario.test)
        
        if not success then
            test_result.status = "error"
            test_result.error = result
            error_tests.summary.errors = error_tests.summary.errors + 1
            log_error("  ✗ Test crashed: " .. (result or "unknown error"))
        elseif result then
            test_result.status = "passed"
            test_result.passed = true
            error_tests.summary.passed = error_tests.summary.passed + 1
            log_info("  ✓ Test passed")
        else
            test_result.status = "failed"
            error_tests.summary.failed = error_tests.summary.failed + 1
            log_info("  ✗ Test failed")
        end
        
        error_tests.tests[scenario.name] = test_result
    end
    
    log_info("=== Error Reproduction Results ===", true)
    log_info(string.format("Passed: %d, Failed: %d, Errors: %d",
             error_tests.summary.passed,
             error_tests.summary.failed, 
             error_tests.summary.errors), true)
    log_info("=== End Error Tests ===", true)
    
    framework_state.test_results.error_reproduction = error_tests
    return error_tests
end

-- User report generation
function M.generate_user_report()
    log_info("Generating user report...", true)
    
    local report = {
        timestamp = os.time(),
        pebble_version = "unknown",
        nvim_version = vim.version(),
        system_info = {
            os = vim.loop.os_uname(),
            working_directory = vim.fn.getcwd(),
        },
        test_results = framework_state.test_results,
        recommendations = {},
        next_steps = {}
    }
    
    -- Analyze results and provide recommendations
    local validation = framework_state.test_results.validation
    local benchmark = framework_state.test_results.performance_benchmark
    local error_tests = framework_state.test_results.error_reproduction
    
    if validation then
        if validation.overall_status == "failed" then
            table.insert(report.recommendations, "Fix setup issues before using Pebble")
            table.insert(report.next_steps, "Review validation errors and follow recommendations")
        elseif validation.overall_status == "warnings" then
            table.insert(report.recommendations, "Address warnings to improve performance")
        else
            table.insert(report.recommendations, "Setup looks good - Pebble should work well")
        end
    end
    
    if benchmark then
        if benchmark.summary.success_rate < 80 then
            table.insert(report.recommendations, "Performance issues detected - check system resources")
        elseif benchmark.summary.avg_performance_ms > 1000 then
            table.insert(report.recommendations, "Completion is slow - consider optimizing or reducing repository size")
        end
        
        if benchmark.summary.avg_performance_ms < 100 then
            table.insert(report.recommendations, "Excellent performance - setup is optimal")
        end
    end
    
    if error_tests then
        local error_rate = (error_tests.summary.errors + error_tests.summary.failed) / 
                          (error_tests.summary.passed + error_tests.summary.failed + error_tests.summary.errors)
        
        if error_rate > 0.5 then
            table.insert(report.recommendations, "High error rate - check installation")
            table.insert(report.next_steps, "Reinstall Pebble or check dependencies")
        elseif error_rate > 0.2 then
            table.insert(report.recommendations, "Some errors detected - monitor for issues")
        end
    end
    
    -- Add general next steps
    if #report.recommendations == 0 then
        table.insert(report.next_steps, "Everything looks good - start using Pebble completion!")
    end
    table.insert(report.next_steps, "Run :PebbleTestCompletion to test in real files")
    table.insert(report.next_steps, "Use :PebbleHealth for ongoing monitoring")
    
    -- Store report
    framework_state.user_reports[report.timestamp] = report
    
    -- Display summary
    log_info("=== USER REPORT SUMMARY ===", true)
    log_info("Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S", report.timestamp), true)
    log_info("Neovim Version: " .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch, true)
    log_info("Working Directory: " .. report.system_info.working_directory, true)
    
    if #report.recommendations > 0 then
        log_info("\nRecommendations:", true)
        for _, rec in ipairs(report.recommendations) do
            log_info("  - " .. rec, true)
        end
    end
    
    if #report.next_steps > 0 then
        log_info("\nNext Steps:", true)
        for _, step in ipairs(report.next_steps) do
            log_info("  - " .. step, true)
        end
    end
    
    log_info("=== END REPORT ===", true)
    
    return report
end

-- Quick diagnostic for common issues
function M.quick_diagnostic()
    log_info("Running quick diagnostic...", true)
    
    local issues_found = {}
    local fixes_suggested = {}
    
    -- Check 1: Is pebble setup called?
    local pebble_ok, pebble = pcall(require, "pebble")
    if not pebble_ok then
        table.insert(issues_found, "Cannot load main pebble module")
        table.insert(fixes_suggested, "Ensure Pebble is installed: :Lazy install pebble.nvim")
        return { issues = issues_found, fixes = fixes_suggested }
    end
    
    -- Check 2: Manager status
    local manager_ok, manager = pcall(require, "pebble.completion.manager")
    if manager_ok then
        local status = manager.get_status()
        if not status or not status.initialized then
            table.insert(issues_found, "Completion manager not initialized")
            table.insert(fixes_suggested, "Add require('pebble').setup() to your Neovim config")
        else
            local source_count = vim.tbl_count(status.registered_sources or {})
            if source_count == 0 then
                table.insert(issues_found, "No completion sources registered")
                table.insert(fixes_suggested, "Install nvim-cmp or blink.cmp")
            end
        end
    end
    
    -- Check 3: Current filetype
    local current_ft = vim.bo.filetype
    if current_ft ~= "markdown" then
        table.insert(issues_found, "Current buffer is not markdown (filetype: " .. current_ft .. ")")
        table.insert(fixes_suggested, "Open a .md file to test completion")
    end
    
    -- Check 4: Root directory
    local completion = require("pebble.completion")
    local root_dir = completion.get_root_dir()
    if not root_dir then
        table.insert(issues_found, "No root directory detected")
        table.insert(fixes_suggested, "Navigate to a git repository or markdown project folder")
    elseif vim.fn.isdirectory(root_dir) == 0 then
        table.insert(issues_found, "Root directory does not exist: " .. root_dir)
    end
    
    local result = {
        timestamp = os.time(),
        issues = issues_found,
        fixes = fixes_suggested,
        status = #issues_found == 0 and "healthy" or "issues_found"
    }
    
    if #issues_found == 0 then
        log_success("✓ Quick diagnostic: No issues found!")
    else
        log_info("✗ Quick diagnostic found " .. #issues_found .. " issues:", true)
        for i, issue in ipairs(issues_found) do
            log_info("  " .. i .. ". " .. issue, true)
            if fixes_suggested[i] then
                log_info("     Fix: " .. fixes_suggested[i], true)
            end
        end
    end
    
    return result
end

-- Configuration
function M.configure(opts)
    framework_state.config = vim.tbl_deep_extend("force", framework_state.config, opts or {})
end

-- Get results
function M.get_results()
    return framework_state.test_results
end

-- Get user reports
function M.get_user_reports()
    return framework_state.user_reports
end

return M
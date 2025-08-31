local M = {}

-- User controls and debug commands for the pebble completion system
local commands = {
    registered = false,
    debug_enabled = false,
    profiler_enabled = false,
}

-- Dependencies
local performance = require("pebble.completion.performance")
local cache = require("pebble.completion.cache")
local async = require("pebble.completion.async")
local auto_tune = require("pebble.completion.auto_tune")

-- Utility functions
local function format_bytes(bytes)
    local units = {"B", "KB", "MB", "GB"}
    local size = bytes
    local unit_index = 1
    
    while size >= 1024 and unit_index < #units do
        size = size / 1024
        unit_index = unit_index + 1
    end
    
    return string.format("%.2f%s", size, units[unit_index])
end

local function format_duration(ms)
    if ms < 1000 then
        return string.format("%dms", math.floor(ms))
    elseif ms < 60000 then
        return string.format("%.1fs", ms / 1000)
    else
        return string.format("%.1fm", ms / 60000)
    end
end

local function print_table(tbl, prefix, max_depth)
    prefix = prefix or ""
    max_depth = max_depth or 3
    
    if max_depth <= 0 then
        print(prefix .. "...")
        return
    end
    
    for key, value in pairs(tbl) do
        local value_str
        if type(value) == "table" then
            print(prefix .. tostring(key) .. ":")
            print_table(value, prefix .. "  ", max_depth - 1)
        else
            if type(value) == "number" and value > 1000 then
                if key:match("time") or key:match("duration") then
                    value_str = format_duration(value)
                elseif key:match("size") or key:match("memory") or key:match("bytes") then
                    value_str = format_bytes(value)
                else
                    value_str = tostring(value)
                end
            else
                value_str = tostring(value)
            end
            print(prefix .. tostring(key) .. ": " .. value_str)
        end
    end
end

-- Command implementations
local function cmd_status()
    print("=== Pebble Completion System Status ===")
    print()
    
    -- Performance metrics
    local perf_metrics = performance.get_metrics()
    print("Performance Metrics:")
    print("  Requests: " .. perf_metrics.completion_requests)
    print("  Cache Hit Rate: " .. math.floor(perf_metrics.cache_hit_rate * 100) .. "%")
    print("  Average Time: " .. format_duration(perf_metrics.completion_avg_time))
    print("  Error Rate: " .. math.floor(perf_metrics.error_rate * 100) .. "%")
    print("  Memory Usage: " .. format_bytes(perf_metrics.cache_memory_usage))
    print()
    
    -- Cache statistics
    local cache_stats = cache.get_stats()
    if cache_stats.global then
        print("Cache Statistics:")
        print("  Total Hit Rate: " .. math.floor(cache_stats.global.hit_rate * 100) .. "%")
        print("  Memory Usage: " .. format_bytes(cache_stats.global.memory_usage))
        print("  Stores: " .. cache_stats.global.stores_count)
        print("  Evictions: " .. cache_stats.global.evictions)
        print()
    end
    
    -- Async statistics
    local async_stats = async.get_stats()
    print("Async System:")
    print("  Running Jobs: " .. async_stats.running_jobs)
    print("  Queued Jobs: " .. async_stats.queued_jobs)
    print("  Completed: " .. async_stats.completed_jobs)
    print("  Failed: " .. async_stats.failed_jobs)
    print("  Average Execution: " .. format_duration(async_stats.avg_execution_time))
    print()
    
    -- Auto-tuning status
    local autotune_stats = auto_tune.get_stats()
    print("Auto-tuning:")
    print("  Enabled: " .. tostring(autotune_stats.enabled))
    print("  Performance Score: " .. math.floor(autotune_stats.current_performance_score * 100) .. "%")
    print("  Iterations: " .. autotune_stats.iteration)
    print("  Parameter Changes: " .. autotune_stats.parameter_changes)
end

local function cmd_health()
    print("=== System Health Check ===")
    print()
    
    -- Performance health
    local perf_health = performance.health_check()
    print("Performance Health: " .. perf_health.status:upper())
    if #perf_health.warnings > 0 then
        print("Warnings:")
        for _, warning in ipairs(perf_health.warnings) do
            print("  - " .. warning)
        end
    end
    if #perf_health.errors > 0 then
        print("Errors:")
        for _, error in ipairs(perf_health.errors) do
            print("  - " .. error)
        end
    end
    if #perf_health.recommendations > 0 then
        print("Recommendations:")
        for _, rec in ipairs(perf_health.recommendations) do
            print("  - " .. rec)
        end
    end
    print()
    
    -- Cache health
    local cache_health = cache.health_check()
    print("Cache Health: " .. cache_health.status:upper())
    if #cache_health.issues > 0 then
        print("Issues:")
        for _, issue in ipairs(cache_health.issues) do
            print("  - " .. issue)
        end
    end
    if #cache_health.recommendations > 0 then
        print("Recommendations:")
        for _, rec in ipairs(cache_health.recommendations) do
            print("  - " .. rec)
        end
    end
    print()
    
    -- Async health
    local async_health = async.health_check()
    print("Async Health: " .. async_health.status:upper())
    if #async_health.issues > 0 then
        print("Issues:")
        for _, issue in ipairs(async_health.issues) do
            print("  - " .. issue)
        end
    end
    if #async_health.recommendations > 0 then
        print("Recommendations:")
        for _, rec in ipairs(async_health.recommendations) do
            print("  - " .. rec)
        end
    end
    print()
    
    -- Auto-tuning health
    local autotune_health = auto_tune.health_check()
    print("Auto-tuning Health: " .. autotune_health.status:upper())
    if #autotune_health.issues > 0 then
        print("Issues:")
        for _, issue in ipairs(autotune_health.issues) do
            print("  - " .. issue)
        end
    end
    if #autotune_health.recommendations > 0 then
        print("Recommendations:")
        for _, rec in ipairs(autotune_health.recommendations) do
            print("  - " .. rec)
        end
    end
end

local function cmd_tune(action)
    if action == "enable" then
        auto_tune.set_enabled(true)
        print("Auto-tuning enabled")
    elseif action == "disable" then
        auto_tune.set_enabled(false)
        print("Auto-tuning disabled")
    elseif action == "trigger" then
        auto_tune.trigger_tuning()
        print("Auto-tuning triggered manually")
    elseif action == "reset" then
        auto_tune.reset()
        print("Auto-tuning state reset")
    elseif action == "params" then
        local params = auto_tune.get_current_parameters()
        print("Current Auto-tuning Parameters:")
        print_table(params)
    elseif action == "recommendations" then
        local recs = auto_tune.get_recommendations()
        print("Auto-tuning Recommendations:")
        for _, rec in ipairs(recs) do
            print(string.format("  %s: %s %s (%s)", rec.type, rec.action, rec.parameter, rec.reason))
        end
    else
        print("Available tune actions: enable, disable, trigger, reset, params, recommendations")
    end
end

local function cmd_cache(action, store_name)
    if action == "clear" then
        cache.clear(store_name)
        if store_name then
            print("Cache store '" .. store_name .. "' cleared")
        else
            print("All cache stores cleared")
        end
    elseif action == "stats" then
        local stats = cache.get_stats(store_name)
        if store_name then
            print("Cache Stats for '" .. store_name .. "':")
            print_table(stats)
        else
            print("Global Cache Stats:")
            print_table(stats)
        end
    elseif action == "config" then
        local config = cache.get_config(store_name)
        if config then
            print("Cache Configuration" .. (store_name and " for '" .. store_name .. "'" or "") .. ":")
            print_table(config)
        else
            print("Cache store not found: " .. (store_name or "unknown"))
        end
    else
        print("Available cache actions: clear [store], stats [store], config [store]")
    end
end

local function cmd_async(action)
    if action == "stats" then
        local stats = async.get_stats()
        print("Async System Stats:")
        print_table(stats)
    elseif action == "cancel" then
        local cancelled = async.cancel_all()
        print("Cancelled " .. cancelled .. " jobs")
    elseif action == "queue" then
        local stats = async.get_stats()
        print("Job Queue Status:")
        print("  Running: " .. stats.running_jobs)
        print("  Queued: " .. stats.queued_jobs)
        print("  Priority Distribution:")
        for priority, count in pairs(stats.queue_priority_distribution or {}) do
            print("    Priority " .. priority .. ": " .. count .. " jobs")
        end
    else
        print("Available async actions: stats, cancel, queue")
    end
end

local function cmd_debug(action)
    if action == "enable" then
        commands.debug_enabled = true
        print("Debug mode enabled")
    elseif action == "disable" then
        commands.debug_enabled = false
        print("Debug mode disabled")
    elseif action == "export" then
        local export_data = {
            performance = performance.export_performance_data(),
            cache = cache.get_stats(),
            async = async.get_stats(),
            auto_tune = auto_tune.export_state(),
            timestamp = vim.loop.now(),
        }
        
        local filename = "pebble_debug_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
        local filepath = vim.fn.getcwd() .. "/" .. filename
        
        local file = io.open(filepath, "w")
        if file then
            file:write(vim.fn.json_encode(export_data))
            file:close()
            print("Debug data exported to: " .. filepath)
        else
            print("Failed to export debug data to: " .. filepath)
        end
    elseif action == "profile" then
        if commands.profiler_enabled then
            commands.profiler_enabled = false
            print("Profiler disabled")
        else
            commands.profiler_enabled = true
            print("Profiler enabled - completion operations will be profiled")
        end
    else
        print("Available debug actions: enable, disable, export, profile")
    end
end

local function cmd_benchmark()
    print("Running performance benchmark...")
    
    local completion = require("pebble.completion")
    local start_time = vim.loop.now()
    
    -- Simulate completion requests
    local test_queries = {"test", "sample", "demo", "completion", "performance"}
    local results = {}
    
    for i, query in ipairs(test_queries) do
        local query_start = vim.loop.now()
        
        -- Simulate wiki link completion
        local root_dir = completion.get_root_dir()
        local completions = completion.get_wiki_completions(query, root_dir)
        
        local query_time = vim.loop.now() - query_start
        results[i] = {
            query = query,
            results_count = #completions,
            time = query_time,
        }
        
        print(string.format("Query '%s': %d results in %s", 
              query, #completions, format_duration(query_time)))
    end
    
    local total_time = vim.loop.now() - start_time
    local avg_time = total_time / #test_queries
    
    print()
    print("Benchmark Results:")
    print("  Total Time: " .. format_duration(total_time))
    print("  Average Time: " .. format_duration(avg_time))
    print("  Total Queries: " .. #test_queries)
    
    -- Test cache performance
    print()
    print("Testing cache performance...")
    local cache_start = vim.loop.now()
    
    for i = 1, 100 do
        cache.set("benchmark", "key_" .. i, "value_" .. i)
    end
    
    local cache_write_time = vim.loop.now() - cache_start
    print("Cache write (100 items): " .. format_duration(cache_write_time))
    
    local cache_read_start = vim.loop.now()
    local hit_count = 0
    
    for i = 1, 100 do
        if cache.get("benchmark", "key_" .. i) then
            hit_count = hit_count + 1
        end
    end
    
    local cache_read_time = vim.loop.now() - cache_read_start
    print("Cache read (100 items): " .. format_duration(cache_read_time))
    print("Cache hit rate: " .. math.floor((hit_count / 100) * 100) .. "%")
    
    -- Clean up benchmark cache
    cache.clear("benchmark")
end

local function cmd_config(component, key, value)
    if component == "performance" then
        local config = {thresholds = {}}
        if key and value then
            config.thresholds[key] = tonumber(value) or value
            performance.setup(config)
            print("Performance config updated: " .. key .. " = " .. tostring(value))
        else
            print("Usage: PebbleConfig performance <threshold_key> <value>")
        end
    elseif component == "cache" then
        local config = {}
        if key and value then
            config[key] = tonumber(value) or value
            cache.configure(nil, config)
            print("Cache config updated: " .. key .. " = " .. tostring(value))
        else
            print("Usage: PebbleConfig cache <config_key> <value>")
        end
    elseif component == "async" then
        local config = {}
        if key and value then
            config[key] = tonumber(value) or value
            async.setup(config)
            print("Async config updated: " .. key .. " = " .. tostring(value))
        else
            print("Usage: PebbleConfig async <config_key> <value>")
        end
    elseif component == "autotune" then
        local config = {}
        if key == "enabled" then
            config.enabled = value == "true"
        elseif key and value then
            config[key] = tonumber(value) or value
        end
        
        if key then
            auto_tune.configure(config)
            print("Auto-tune config updated: " .. key .. " = " .. tostring(value))
        else
            print("Usage: PebbleConfig autotune <config_key> <value>")
        end
    else
        print("Available components: performance, cache, async, autotune")
    end
end

-- Emergency disable function
local function cmd_emergency_disable()
    print("EMERGENCY: Disabling all pebble completion systems...")
    
    -- Disable auto-tuning
    auto_tune.set_enabled(false)
    
    -- Cancel all async jobs
    async.cancel_all()
    
    -- Clear all caches
    cache.clear()
    
    -- Reset performance metrics
    performance.reset_metrics()
    
    print("All systems disabled. Use PebbleEnable to re-enable.")
end

local function cmd_enable()
    print("Re-enabling pebble completion systems...")
    
    -- Re-enable auto-tuning
    auto_tune.set_enabled(true)
    
    print("Systems re-enabled.")
end

-- Register all commands
function M.register_commands()
    if commands.registered then return end
    
    -- Status and health commands
    vim.api.nvim_create_user_command("PebbleStatus", function()
        cmd_status()
    end, { desc = "Show pebble completion system status" })
    
    vim.api.nvim_create_user_command("PebbleHealth", function()
        cmd_health()
    end, { desc = "Perform system health check" })
    
    -- Auto-tuning commands
    vim.api.nvim_create_user_command("PebbleTune", function(args)
        cmd_tune(args.args)
    end, { 
        nargs = 1, 
        complete = function()
            return {"enable", "disable", "trigger", "reset", "params", "recommendations"}
        end,
        desc = "Auto-tuning controls" 
    })
    
    -- Cache commands
    vim.api.nvim_create_user_command("PebbleCache", function(args)
        local action = args.fargs[1]
        local store_name = args.fargs[2]
        cmd_cache(action, store_name)
    end, { 
        nargs = "*", 
        complete = function(arg_lead, cmd_line, cursor_pos)
            local args = vim.split(cmd_line, "%s+")
            if #args <= 2 then
                return {"clear", "stats", "config"}
            elseif #args == 3 and args[2] == "clear" or args[2] == "stats" or args[2] == "config" then
                return {"completion", "notes", "tags"}
            end
            return {}
        end,
        desc = "Cache management commands" 
    })
    
    -- Async commands
    vim.api.nvim_create_user_command("PebbleAsync", function(args)
        cmd_async(args.args)
    end, { 
        nargs = 1, 
        complete = function()
            return {"stats", "cancel", "queue"}
        end,
        desc = "Async system controls" 
    })
    
    -- Debug commands
    vim.api.nvim_create_user_command("PebbleDebug", function(args)
        cmd_debug(args.args)
    end, { 
        nargs = 1, 
        complete = function()
            return {"enable", "disable", "export", "profile"}
        end,
        desc = "Debug and profiling controls" 
    })
    
    -- Benchmark command
    vim.api.nvim_create_user_command("PebbleBenchmark", function()
        cmd_benchmark()
    end, { desc = "Run performance benchmark" })
    
    -- Configuration command
    vim.api.nvim_create_user_command("PebbleConfig", function(args)
        local component = args.fargs[1]
        local key = args.fargs[2]
        local value = args.fargs[3]
        cmd_config(component, key, value)
    end, { 
        nargs = "*", 
        complete = function(arg_lead, cmd_line, cursor_pos)
            local args = vim.split(cmd_line, "%s+")
            if #args <= 2 then
                return {"performance", "cache", "async", "autotune"}
            end
            return {}
        end,
        desc = "Configuration management" 
    })
    
    -- Emergency commands
    vim.api.nvim_create_user_command("PebbleEmergencyDisable", function()
        cmd_emergency_disable()
    end, { desc = "Emergency disable all systems" })
    
    vim.api.nvim_create_user_command("PebbleEnable", function()
        cmd_enable()
    end, { desc = "Re-enable systems after emergency disable" })
    
    commands.registered = true
end

-- Debug logging function
function M.debug_log(message, level)
    if not commands.debug_enabled then return end
    
    level = level or vim.log.levels.DEBUG
    local timestamp = os.date("%H:%M:%S")
    vim.notify(string.format("[%s] Pebble Debug: %s", timestamp, message), level)
end

-- Profile a function execution
function M.profile_function(func_name, func)
    if not commands.profiler_enabled then
        return func()
    end
    
    local start_time = vim.loop.now()
    local memory_before = collectgarbage("count") * 1024
    
    local results = func()
    
    local end_time = vim.loop.now()
    local memory_after = collectgarbage("count") * 1024
    
    local execution_time = end_time - start_time
    local memory_used = memory_after - memory_before
    
    M.debug_log(string.format("Profile[%s]: %s (memory: %s)", 
                func_name, 
                format_duration(execution_time),
                format_bytes(memory_used)))
    
    return results
end

-- Get debug status
function M.get_debug_status()
    return {
        debug_enabled = commands.debug_enabled,
        profiler_enabled = commands.profiler_enabled,
        commands_registered = commands.registered,
    }
end

-- Setup function
function M.setup(config)
    config = config or {}
    
    -- Register commands
    M.register_commands()
    
    -- Set initial debug state
    if config.debug_enabled then
        commands.debug_enabled = config.debug_enabled
    end
    
    if config.profiler_enabled then
        commands.profiler_enabled = config.profiler_enabled
    end
    
    -- Create autocommand for debug logging
    if commands.debug_enabled then
        vim.api.nvim_create_augroup("PebbleDebug", { clear = true })
        vim.api.nvim_create_autocmd("User", {
            pattern = "PebblePerformanceUpdate",
            group = "PebbleDebug",
            callback = function(args)
                M.debug_log("Performance update: " .. vim.inspect(args.data))
            end,
        })
    end
    
    return true
end

return M
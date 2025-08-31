-- Monitoring Tools
-- Performance metrics collection, error logging, debug commands, and health checks
local M = {}

-- Monitoring state
local monitoring_state = {
    enabled = false,
    start_time = nil,
    performance_metrics = {},
    error_log = {},
    debug_log = {},
    health_checks = {},
    watchers = {},
    config = {
        max_error_entries = 100,
        max_debug_entries = 500,
        max_performance_entries = 200,
        performance_threshold_warning_ms = 500,
        performance_threshold_error_ms = 1000,
        health_check_interval_ms = 30000, -- 30 seconds
        auto_cleanup_interval_ms = 300000, -- 5 minutes
    }
}

-- Logging utilities
local function log_info(msg)
    print("[PEBBLE MONITOR] " .. msg)
end

local function log_debug(msg)
    if monitoring_state.enabled then
        print("[PEBBLE MONITOR DEBUG] " .. msg)
    end
end

-- Performance metrics collection
local function add_performance_metric(operation, duration_ms, metadata)
    local metric = {
        timestamp = os.time(),
        operation = operation,
        duration_ms = duration_ms,
        metadata = metadata or {},
        level = duration_ms > monitoring_state.config.performance_threshold_error_ms and "error" or
                duration_ms > monitoring_state.config.performance_threshold_warning_ms and "warning" or "info"
    }
    
    table.insert(monitoring_state.performance_metrics, metric)
    
    -- Trim old entries
    while #monitoring_state.performance_metrics > monitoring_state.config.max_performance_entries do
        table.remove(monitoring_state.performance_metrics, 1)
    end
    
    -- Log warning/error performance issues
    if metric.level == "warning" then
        log_debug("Performance warning: " .. operation .. " took " .. duration_ms .. "ms")
    elseif metric.level == "error" then
        log_info("Performance error: " .. operation .. " took " .. duration_ms .. "ms")
    end
    
    return metric
end

-- Performance timer utility
function M.start_performance_timer(operation)
    local start_time = vim.loop.hrtime()
    local metadata = {}
    
    return {
        add_metadata = function(key, value)
            metadata[key] = value
        end,
        stop = function()
            local end_time = vim.loop.hrtime()
            local duration_ms = (end_time - start_time) / 1000000
            return add_performance_metric(operation, duration_ms, metadata)
        end
    }
end

-- Error logging
local function add_error_log(error_type, message, context)
    local error_entry = {
        timestamp = os.time(),
        type = error_type,
        message = message,
        context = context or {},
        stack_trace = debug.traceback()
    }
    
    table.insert(monitoring_state.error_log, error_entry)
    
    -- Trim old entries
    while #monitoring_state.error_log > monitoring_state.config.max_error_entries do
        table.remove(monitoring_state.error_log, 1)
    end
    
    log_info("Error logged: " .. error_type .. " - " .. message)
    return error_entry
end

function M.log_error(error_type, message, context)
    if not monitoring_state.enabled then return end
    return add_error_log(error_type, message, context)
end

-- Debug logging
function M.log_debug(operation, message, data)
    if not monitoring_state.enabled then return end
    
    local debug_entry = {
        timestamp = os.time(),
        operation = operation,
        message = message,
        data = data or {}
    }
    
    table.insert(monitoring_state.debug_log, debug_entry)
    
    -- Trim old entries
    while #monitoring_state.debug_log > monitoring_state.config.max_debug_entries do
        table.remove(monitoring_state.debug_log, 1)
    end
    
    log_debug(operation .. ": " .. message)
    return debug_entry
end

-- Health check functions
local function check_completion_system_health()
    local health = {
        name = "completion_system",
        timestamp = os.time(),
        status = "healthy",
        issues = {},
        metrics = {}
    }
    
    -- Test basic completion functionality
    local timer = M.start_performance_timer("health_check_completion")
    
    local success, result = pcall(function()
        local completion = require("pebble.completion")
        
        -- Check if completion is available
        if not completion.is_completion_enabled then
            table.insert(health.issues, "Completion module missing is_completion_enabled function")
            return false
        end
        
        -- Check cache stats
        local stats = completion.get_stats()
        if not stats then
            table.insert(health.issues, "Unable to get completion stats")
            return false
        end
        
        health.metrics.cache_size = stats.cache_size or 0
        health.metrics.cache_age_ms = stats.cache_age or 0
        health.metrics.cache_valid = stats.cache_valid or false
        
        -- Warn if cache is very old
        if stats.cache_age and stats.cache_age > 300000 then  -- 5 minutes
            table.insert(health.issues, "Cache is very old (" .. math.floor(stats.cache_age / 1000) .. "s)")
        end
        
        return true
    end)
    
    local metric = timer.stop()
    health.metrics.health_check_duration_ms = metric.duration_ms
    
    if not success then
        health.status = "unhealthy"
        table.insert(health.issues, "Completion system check failed: " .. (result or "unknown error"))
    elseif #health.issues > 0 then
        health.status = "degraded"
    end
    
    return health
end

local function check_cache_system_health()
    local health = {
        name = "cache_system", 
        timestamp = os.time(),
        status = "healthy",
        issues = {},
        metrics = {}
    }
    
    local timer = M.start_performance_timer("health_check_cache")
    
    local success, result = pcall(function()
        local completion = require("pebble.completion")
        
        -- Test cache operations
        local initial_stats = completion.get_stats()
        
        -- Test cache invalidation
        completion.invalidate_cache()
        local post_invalidation_stats = completion.get_stats()
        
        health.metrics.cache_invalidation_works = not post_invalidation_stats.cache_valid
        
        if post_invalidation_stats.cache_valid then
            table.insert(health.issues, "Cache invalidation not working properly")
        end
        
        -- Check if cache can rebuild
        local root_dir = completion.get_root_dir()
        if root_dir then
            local completions = completion.get_wiki_completions("", root_dir)
            health.metrics.cache_rebuild_result_count = #completions
            
            local final_stats = completion.get_stats()
            health.metrics.cache_rebuilt = final_stats.cache_valid
            
            if not final_stats.cache_valid then
                table.insert(health.issues, "Cache failed to rebuild after invalidation")
            end
        else
            table.insert(health.issues, "Unable to determine root directory for cache test")
        end
        
        return true
    end)
    
    local metric = timer.stop()
    health.metrics.health_check_duration_ms = metric.duration_ms
    
    if not success then
        health.status = "unhealthy"
        table.insert(health.issues, "Cache system check failed: " .. (result or "unknown error"))
    elseif #health.issues > 0 then
        health.status = "degraded"
    end
    
    return health
end

local function check_search_system_health()
    local health = {
        name = "search_system",
        timestamp = os.time(), 
        status = "healthy",
        issues = {},
        metrics = {}
    }
    
    local timer = M.start_performance_timer("health_check_search")
    
    local success, result = pcall(function()
        local search = require("pebble.bases.search")
        
        -- Check if ripgrep is available
        health.metrics.has_ripgrep = search.has_ripgrep()
        
        if not health.metrics.has_ripgrep then
            table.insert(health.issues, "ripgrep not available - search will be slower")
        end
        
        -- Check root directory detection
        local root_dir = search.get_root_dir()
        health.metrics.root_dir = root_dir
        health.metrics.root_dir_exists = root_dir and vim.fn.isdirectory(root_dir) == 1
        
        if not health.metrics.root_dir_exists then
            table.insert(health.issues, "Root directory not found or invalid: " .. (root_dir or "nil"))
        end
        
        -- Test file search if root dir is valid
        if health.metrics.root_dir_exists then
            local md_files = search.find_markdown_files_sync(root_dir)
            health.metrics.markdown_files_found = #md_files
            
            if #md_files == 0 then
                table.insert(health.issues, "No markdown files found in root directory")
            end
        end
        
        return true
    end)
    
    local metric = timer.stop()
    health.metrics.health_check_duration_ms = metric.duration_ms
    
    if not success then
        health.status = "unhealthy"
        table.insert(health.issues, "Search system check failed: " .. (result or "unknown error"))
    elseif #health.issues > 0 then
        health.status = "degraded"
    end
    
    return health
end

local function check_completion_sources_health()
    local health = {
        name = "completion_sources",
        timestamp = os.time(),
        status = "healthy", 
        issues = {},
        metrics = {}
    }
    
    local timer = M.start_performance_timer("health_check_sources")
    
    local success, result = pcall(function()
        local completion_manager = require("pebble.completion.manager")
        
        -- Get manager status
        local status = completion_manager.get_status()
        
        if not status then
            table.insert(health.issues, "Unable to get completion manager status")
            return false
        end
        
        health.metrics.manager_initialized = status.initialized
        health.metrics.registered_sources = status.registered_sources or {}
        health.metrics.available_engines = status.available_engines or {}
        
        if not status.initialized then
            table.insert(health.issues, "Completion manager not initialized")
        end
        
        -- Check if any sources are registered
        local source_count = 0
        for _, _ in pairs(health.metrics.registered_sources) do
            source_count = source_count + 1
        end
        
        health.metrics.registered_source_count = source_count
        
        if source_count == 0 then
            table.insert(health.issues, "No completion sources registered")
        end
        
        -- Check available engines
        local engine_count = 0
        for engine, available in pairs(health.metrics.available_engines) do
            if available then engine_count = engine_count + 1 end
        end
        
        health.metrics.available_engine_count = engine_count
        
        if engine_count == 0 then
            table.insert(health.issues, "No completion engines available")
        end
        
        return true
    end)
    
    local metric = timer.stop()
    health.metrics.health_check_duration_ms = metric.duration_ms
    
    if not success then
        health.status = "unhealthy"
        table.insert(health.issues, "Completion sources check failed: " .. (result or "unknown error"))
    elseif #health.issues > 0 then
        health.status = "degraded"
    end
    
    return health
end

-- Run all health checks
function M.run_health_checks()
    local health_checks = {
        check_completion_system_health(),
        check_cache_system_health(),
        check_search_system_health(),
        check_completion_sources_health()
    }
    
    -- Store in monitoring state
    monitoring_state.health_checks = health_checks
    
    -- Calculate overall health
    local healthy_count = 0
    local degraded_count = 0
    local unhealthy_count = 0
    
    for _, check in ipairs(health_checks) do
        if check.status == "healthy" then
            healthy_count = healthy_count + 1
        elseif check.status == "degraded" then
            degraded_count = degraded_count + 1
        else
            unhealthy_count = unhealthy_count + 1
        end
    end
    
    local overall_status = "healthy"
    if unhealthy_count > 0 then
        overall_status = "unhealthy"
    elseif degraded_count > 0 then
        overall_status = "degraded"
    end
    
    local summary = {
        overall_status = overall_status,
        timestamp = os.time(),
        healthy_count = healthy_count,
        degraded_count = degraded_count,
        unhealthy_count = unhealthy_count,
        total_count = #health_checks,
        checks = health_checks
    }
    
    log_info("Health check completed: " .. overall_status .. " (" .. 
             healthy_count .. " healthy, " .. degraded_count .. " degraded, " .. 
             unhealthy_count .. " unhealthy)")
    
    return summary
end

-- Memory usage monitoring
function M.get_memory_usage()
    local before_gc = collectgarbage("count")
    collectgarbage("collect")
    local after_gc = collectgarbage("count")
    
    return {
        timestamp = os.time(),
        memory_kb_before_gc = before_gc,
        memory_kb_after_gc = after_gc,
        memory_mb_after_gc = after_gc / 1024,
        freed_kb = before_gc - after_gc
    }
end

-- Monitoring startup and shutdown
function M.start_monitoring(config)
    if monitoring_state.enabled then
        log_info("Monitoring already enabled")
        return true
    end
    
    -- Update config
    if config then
        monitoring_state.config = vim.tbl_deep_extend("force", monitoring_state.config, config)
    end
    
    monitoring_state.enabled = true
    monitoring_state.start_time = os.time()
    
    log_info("Monitoring started")
    
    -- Setup periodic health checks
    if monitoring_state.config.health_check_interval_ms > 0 then
        local health_timer = vim.loop.new_timer()
        health_timer:start(monitoring_state.config.health_check_interval_ms, 
                          monitoring_state.config.health_check_interval_ms, 
                          function()
                            M.run_health_checks()
                          end)
        monitoring_state.watchers.health_timer = health_timer
    end
    
    -- Setup periodic cleanup
    if monitoring_state.config.auto_cleanup_interval_ms > 0 then
        local cleanup_timer = vim.loop.new_timer()
        cleanup_timer:start(monitoring_state.config.auto_cleanup_interval_ms,
                           monitoring_state.config.auto_cleanup_interval_ms,
                           function()
                             M.cleanup_old_entries()
                           end)
        monitoring_state.watchers.cleanup_timer = cleanup_timer
    end
    
    return true
end

function M.stop_monitoring()
    if not monitoring_state.enabled then
        return false
    end
    
    monitoring_state.enabled = false
    
    -- Stop watchers
    for _, timer in pairs(monitoring_state.watchers) do
        if timer and timer.close then
            timer:close()
        end
    end
    monitoring_state.watchers = {}
    
    log_info("Monitoring stopped")
    return true
end

-- Cleanup old entries
function M.cleanup_old_entries()
    local cleaned = {
        performance = 0,
        errors = 0,
        debug = 0
    }
    
    -- Clean performance metrics (keep only recent ones)
    local keep_performance_after = os.time() - 3600  -- Keep last hour
    local new_performance = {}
    for _, metric in ipairs(monitoring_state.performance_metrics) do
        if metric.timestamp > keep_performance_after then
            table.insert(new_performance, metric)
        else
            cleaned.performance = cleaned.performance + 1
        end
    end
    monitoring_state.performance_metrics = new_performance
    
    -- Clean error log (keep more errors for debugging)
    local keep_errors_after = os.time() - 7200  -- Keep last 2 hours
    local new_errors = {}
    for _, error in ipairs(monitoring_state.error_log) do
        if error.timestamp > keep_errors_after then
            table.insert(new_errors, error)
        else
            cleaned.errors = cleaned.errors + 1
        end
    end
    monitoring_state.error_log = new_errors
    
    -- Clean debug log (keep less debug info)
    local keep_debug_after = os.time() - 1800  -- Keep last 30 minutes  
    local new_debug = {}
    for _, debug in ipairs(monitoring_state.debug_log) do
        if debug.timestamp > keep_debug_after then
            table.insert(new_debug, debug)
        else
            cleaned.debug = cleaned.debug + 1
        end
    end
    monitoring_state.debug_log = new_debug
    
    if cleaned.performance + cleaned.errors + cleaned.debug > 0 then
        log_debug("Cleaned up " .. (cleaned.performance + cleaned.errors + cleaned.debug) .. " old monitoring entries")
    end
    
    return cleaned
end

-- Get monitoring report
function M.get_monitoring_report()
    local uptime_seconds = monitoring_state.start_time and (os.time() - monitoring_state.start_time) or 0
    
    -- Performance statistics
    local perf_stats = {
        total_operations = #monitoring_state.performance_metrics,
        warning_count = 0,
        error_count = 0,
        avg_duration_ms = 0
    }
    
    if #monitoring_state.performance_metrics > 0 then
        local total_duration = 0
        for _, metric in ipairs(monitoring_state.performance_metrics) do
            total_duration = total_duration + metric.duration_ms
            if metric.level == "warning" then
                perf_stats.warning_count = perf_stats.warning_count + 1
            elseif metric.level == "error" then
                perf_stats.error_count = perf_stats.error_count + 1
            end
        end
        perf_stats.avg_duration_ms = total_duration / #monitoring_state.performance_metrics
    end
    
    -- Error statistics
    local error_stats = {
        total_errors = #monitoring_state.error_log,
        error_types = {}
    }
    
    for _, error in ipairs(monitoring_state.error_log) do
        error_stats.error_types[error.type] = (error_stats.error_types[error.type] or 0) + 1
    end
    
    -- Memory usage
    local memory_info = M.get_memory_usage()
    
    return {
        enabled = monitoring_state.enabled,
        uptime_seconds = uptime_seconds,
        performance_stats = perf_stats,
        error_stats = error_stats,
        memory_usage = memory_info,
        debug_entries = #monitoring_state.debug_log,
        health_checks = monitoring_state.health_checks,
        config = monitoring_state.config
    }
end

-- Get recent performance metrics
function M.get_recent_performance_metrics(operation, limit)
    limit = limit or 10
    local metrics = {}
    
    for i = #monitoring_state.performance_metrics, 1, -1 do
        local metric = monitoring_state.performance_metrics[i]
        if not operation or metric.operation == operation then
            table.insert(metrics, metric)
            if #metrics >= limit then
                break
            end
        end
    end
    
    return metrics
end

-- Get recent errors
function M.get_recent_errors(error_type, limit)
    limit = limit or 10
    local errors = {}
    
    for i = #monitoring_state.error_log, 1, -1 do
        local error = monitoring_state.error_log[i]
        if not error_type or error.type == error_type then
            table.insert(errors, error)
            if #errors >= limit then
                break
            end
        end
    end
    
    return errors
end

return M
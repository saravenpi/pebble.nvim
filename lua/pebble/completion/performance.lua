local M = {}

-- Performance monitoring and metrics system
local performance = {
    metrics = {
        -- Completion metrics
        completion_requests = 0,
        completion_cache_hits = 0,
        completion_cache_misses = 0,
        completion_avg_time = 0,
        completion_errors = 0,
        
        -- Cache metrics
        cache_size = 0,
        cache_memory_usage = 0,
        cache_evictions = 0,
        cache_ttl_expires = 0,
        
        -- File operations
        file_scan_count = 0,
        file_scan_avg_time = 0,
        file_read_errors = 0,
        
        -- System resources
        memory_pressure = false,
        cpu_usage = 0,
        
        -- User experience
        ui_freeze_count = 0,
        timeout_count = 0,
    },
    
    timers = {},
    history = {},
    max_history_size = 1000,
    
    -- Performance thresholds
    thresholds = {
        completion_max_time = 500,  -- 500ms max for completion
        cache_max_memory = 50 * 1024 * 1024, -- 50MB max cache memory
        max_ui_freeze_time = 100,   -- 100ms max UI freeze
        max_file_scan_time = 2000,  -- 2s max file scan
    },
    
    -- Auto-tuning parameters
    auto_tune = {
        enabled = true,
        cache_ttl_base = 30000,     -- 30s base TTL
        cache_ttl_current = 30000,
        cache_size_limit = 2000,
        batch_size = 25,
        max_concurrent_ops = 3,
    },
}

-- Performance timer utility
local function start_timer(name)
    performance.timers[name] = vim.loop.hrtime()
end

local function end_timer(name)
    if performance.timers[name] then
        local elapsed = (vim.loop.hrtime() - performance.timers[name]) / 1000000 -- Convert to milliseconds
        performance.timers[name] = nil
        return elapsed
    end
    return 0
end

-- Memory usage estimation
local function estimate_memory_usage(obj)
    local seen = {}
    local function calc_size(o)
        if seen[o] then return 0 end
        seen[o] = true
        
        local t = type(o)
        if t == "string" then
            return #o + 24 -- String overhead
        elseif t == "number" then
            return 8
        elseif t == "boolean" then
            return 4
        elseif t == "table" then
            local size = 40 -- Table overhead
            for k, v in pairs(o) do
                size = size + calc_size(k) + calc_size(v)
            end
            return size
        end
        return 0
    end
    
    return calc_size(obj)
end

-- Record performance metrics
local function record_metric(metric_name, value, timestamp)
    timestamp = timestamp or vim.loop.now()
    
    if not performance.history[metric_name] then
        performance.history[metric_name] = {}
    end
    
    table.insert(performance.history[metric_name], {
        value = value,
        timestamp = timestamp
    })
    
    -- Limit history size
    local history = performance.history[metric_name]
    if #history > performance.max_history_size then
        table.remove(history, 1)
    end
end

-- Calculate moving average
local function calculate_moving_average(metric_name, window_size)
    window_size = window_size or 10
    local history = performance.history[metric_name]
    
    if not history or #history == 0 then
        return 0
    end
    
    local start_idx = math.max(1, #history - window_size + 1)
    local sum = 0
    local count = 0
    
    for i = start_idx, #history do
        sum = sum + history[i].value
        count = count + 1
    end
    
    return count > 0 and (sum / count) or 0
end

-- Detect memory pressure
local function detect_memory_pressure()
    -- Simple heuristic based on cache size and system responsiveness
    local cache_memory = performance.metrics.cache_memory_usage
    local max_memory = performance.thresholds.cache_max_memory
    
    if cache_memory > max_memory * 0.8 then
        performance.metrics.memory_pressure = true
        return true
    end
    
    performance.metrics.memory_pressure = false
    return false
end

-- Auto-tuning system
local function auto_tune_performance()
    if not performance.auto_tune.enabled then
        return
    end
    
    local avg_completion_time = calculate_moving_average("completion_time", 20)
    local cache_hit_rate = performance.metrics.completion_cache_hits / 
                          math.max(1, performance.metrics.completion_cache_hits + performance.metrics.completion_cache_misses)
    
    -- Adjust cache TTL based on performance
    if avg_completion_time > performance.thresholds.completion_max_time then
        -- Slow completions, increase cache TTL
        performance.auto_tune.cache_ttl_current = math.min(120000, performance.auto_tune.cache_ttl_current * 1.5)
    elseif avg_completion_time < performance.thresholds.completion_max_time / 2 and cache_hit_rate > 0.8 then
        -- Fast completions with good hit rate, can reduce TTL for fresher data
        performance.auto_tune.cache_ttl_current = math.max(15000, performance.auto_tune.cache_ttl_current * 0.8)
    end
    
    -- Adjust batch size based on UI responsiveness
    if performance.metrics.ui_freeze_count > 5 then
        performance.auto_tune.batch_size = math.max(10, performance.auto_tune.batch_size - 5)
        performance.metrics.ui_freeze_count = 0 -- Reset counter
    elseif avg_completion_time < 100 then
        performance.auto_tune.batch_size = math.min(50, performance.auto_tune.batch_size + 5)
    end
    
    -- Adjust concurrent operations based on errors
    if performance.metrics.timeout_count > 3 then
        performance.auto_tune.max_concurrent_ops = math.max(1, performance.auto_tune.max_concurrent_ops - 1)
        performance.metrics.timeout_count = 0 -- Reset counter
    elseif performance.metrics.timeout_count == 0 and avg_completion_time < 200 then
        performance.auto_tune.max_concurrent_ops = math.min(5, performance.auto_tune.max_concurrent_ops + 1)
    end
    
    -- Memory pressure handling
    if detect_memory_pressure() then
        performance.auto_tune.cache_size_limit = math.max(500, performance.auto_tune.cache_size_limit * 0.8)
        -- Trigger cache cleanup
        M.cleanup_cache()
    end
end

-- Start monitoring a completion operation
function M.start_completion_monitoring(operation_id)
    start_timer("completion_" .. operation_id)
    performance.metrics.completion_requests = performance.metrics.completion_requests + 1
end

-- End monitoring a completion operation
function M.end_completion_monitoring(operation_id, cache_hit, error_occurred)
    local elapsed = end_timer("completion_" .. operation_id)
    
    -- Update metrics
    if cache_hit then
        performance.metrics.completion_cache_hits = performance.metrics.completion_cache_hits + 1
    else
        performance.metrics.completion_cache_misses = performance.metrics.completion_cache_misses + 1
    end
    
    if error_occurred then
        performance.metrics.completion_errors = performance.metrics.completion_errors + 1
    end
    
    -- Update average completion time
    local total_requests = performance.metrics.completion_requests
    performance.metrics.completion_avg_time = 
        ((performance.metrics.completion_avg_time * (total_requests - 1)) + elapsed) / total_requests
    
    -- Record for history
    record_metric("completion_time", elapsed)
    
    -- Check for UI freeze
    if elapsed > performance.thresholds.max_ui_freeze_time then
        performance.metrics.ui_freeze_count = performance.metrics.ui_freeze_count + 1
    end
    
    -- Auto-tune based on performance
    vim.schedule(auto_tune_performance)
    
    return elapsed
end

-- Monitor file scanning operations
function M.monitor_file_scan(operation_func)
    start_timer("file_scan")
    performance.metrics.file_scan_count = performance.metrics.file_scan_count + 1
    
    local success, result = pcall(operation_func)
    local elapsed = end_timer("file_scan")
    
    if success then
        -- Update average scan time
        local total_scans = performance.metrics.file_scan_count
        performance.metrics.file_scan_avg_time = 
            ((performance.metrics.file_scan_avg_time * (total_scans - 1)) + elapsed) / total_scans
        
        record_metric("file_scan_time", elapsed)
        return result
    else
        performance.metrics.file_read_errors = performance.metrics.file_read_errors + 1
        return nil
    end
end

-- Update cache metrics
function M.update_cache_metrics(cache_data)
    if cache_data then
        performance.metrics.cache_size = type(cache_data) == "table" and vim.tbl_count(cache_data) or 0
        performance.metrics.cache_memory_usage = estimate_memory_usage(cache_data)
    end
end

-- Record cache eviction
function M.record_cache_eviction(reason)
    performance.metrics.cache_evictions = performance.metrics.cache_evictions + 1
    record_metric("cache_eviction", 1, vim.loop.now())
end

-- Record timeout
function M.record_timeout(operation_type)
    performance.metrics.timeout_count = performance.metrics.timeout_count + 1
    record_metric("timeout", 1, vim.loop.now())
end

-- Get current performance metrics
function M.get_metrics()
    local metrics = vim.deepcopy(performance.metrics)
    
    -- Add calculated metrics
    metrics.cache_hit_rate = metrics.completion_cache_hits / 
                            math.max(1, metrics.completion_cache_hits + metrics.completion_cache_misses)
    metrics.error_rate = metrics.completion_errors / math.max(1, metrics.completion_requests)
    metrics.memory_usage_mb = metrics.cache_memory_usage / (1024 * 1024)
    
    -- Add auto-tune status
    metrics.auto_tune = vim.deepcopy(performance.auto_tune)
    
    return metrics
end

-- Get performance history for a specific metric
function M.get_metric_history(metric_name, limit)
    limit = limit or 100
    local history = performance.history[metric_name]
    
    if not history then
        return {}
    end
    
    local start_idx = math.max(1, #history - limit + 1)
    local result = {}
    
    for i = start_idx, #history do
        table.insert(result, history[i])
    end
    
    return result
end

-- Performance health check
function M.health_check()
    local health = {
        status = "healthy",
        warnings = {},
        errors = {},
        recommendations = {}
    }
    
    local metrics = M.get_metrics()
    
    -- Check completion performance
    if metrics.completion_avg_time > performance.thresholds.completion_max_time then
        table.insert(health.warnings, "Average completion time (" .. 
                    math.floor(metrics.completion_avg_time) .. "ms) exceeds threshold (" .. 
                    performance.thresholds.completion_max_time .. "ms)")
        table.insert(health.recommendations, "Consider increasing cache TTL or reducing file scan scope")
    end
    
    -- Check cache hit rate
    if metrics.cache_hit_rate < 0.5 then
        table.insert(health.warnings, "Low cache hit rate (" .. 
                    math.floor(metrics.cache_hit_rate * 100) .. "%)")
        table.insert(health.recommendations, "Consider increasing cache TTL or reviewing cache invalidation")
    end
    
    -- Check memory usage
    if metrics.memory_pressure then
        table.insert(health.warnings, "Memory pressure detected (" .. 
                    math.floor(metrics.memory_usage_mb) .. "MB)")
        table.insert(health.recommendations, "Consider reducing cache size or enabling more aggressive cleanup")
    end
    
    -- Check error rates
    if metrics.error_rate > 0.1 then
        table.insert(health.errors, "High error rate (" .. 
                    math.floor(metrics.error_rate * 100) .. "%)")
        health.status = "degraded"
    end
    
    -- Check UI responsiveness
    if metrics.ui_freeze_count > 0 then
        table.insert(health.warnings, "UI freezes detected (" .. metrics.ui_freeze_count .. ")")
        table.insert(health.recommendations, "Consider reducing batch size or enabling async processing")
    end
    
    if #health.errors > 0 then
        health.status = "unhealthy"
    elseif #health.warnings > 0 then
        health.status = "degraded"
    end
    
    return health
end

-- Reset all metrics
function M.reset_metrics()
    performance.metrics = {
        completion_requests = 0,
        completion_cache_hits = 0,
        completion_cache_misses = 0,
        completion_avg_time = 0,
        completion_errors = 0,
        cache_size = 0,
        cache_memory_usage = 0,
        cache_evictions = 0,
        cache_ttl_expires = 0,
        file_scan_count = 0,
        file_scan_avg_time = 0,
        file_read_errors = 0,
        memory_pressure = false,
        cpu_usage = 0,
        ui_freeze_count = 0,
        timeout_count = 0,
    }
    
    performance.history = {}
end

-- Cleanup cache based on performance metrics
function M.cleanup_cache()
    -- This function should be called by the cache system
    -- when memory pressure is detected
    performance.metrics.cache_evictions = performance.metrics.cache_evictions + 1
    return true
end

-- Configure performance monitoring
function M.setup(config)
    config = config or {}
    
    -- Update thresholds
    if config.thresholds then
        performance.thresholds = vim.tbl_deep_extend("force", performance.thresholds, config.thresholds)
    end
    
    -- Update auto-tune settings
    if config.auto_tune then
        performance.auto_tune = vim.tbl_deep_extend("force", performance.auto_tune, config.auto_tune)
    end
    
    -- Enable/disable auto-tuning
    if config.auto_tune_enabled ~= nil then
        performance.auto_tune.enabled = config.auto_tune_enabled
    end
    
    -- Start periodic health checks
    if config.health_check_interval and config.health_check_interval > 0 then
        local timer = vim.loop.new_timer()
        timer:start(config.health_check_interval, config.health_check_interval, vim.schedule_wrap(function()
            local health = M.health_check()
            if health.status ~= "healthy" and config.on_health_change then
                config.on_health_change(health)
            end
        end))
    end
    
    return true
end

-- Get current auto-tune parameters
function M.get_auto_tune_params()
    return vim.deepcopy(performance.auto_tune)
end

-- Manually trigger auto-tuning
function M.trigger_auto_tune()
    auto_tune_performance()
end

-- Export performance data for analysis
function M.export_performance_data()
    return {
        metrics = performance.metrics,
        history = performance.history,
        thresholds = performance.thresholds,
        auto_tune = performance.auto_tune,
        timestamp = vim.loop.now()
    }
end

return M
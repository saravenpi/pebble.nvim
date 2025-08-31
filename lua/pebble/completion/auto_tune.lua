local M = {}

-- Auto-tuning system for dynamic performance optimization
local auto_tune = {
    enabled = true,
    learning_rate = 0.1,
    
    -- Parameters to tune
    parameters = {
        cache_ttl = {
            current = 60000, -- 1 minute
            min = 10000,     -- 10 seconds
            max = 300000,    -- 5 minutes
            target_metric = "cache_hit_rate",
            target_value = 0.8,
            adjustment_factor = 1.2,
        },
        
        batch_size = {
            current = 25,
            min = 5,
            max = 100,
            target_metric = "avg_completion_time",
            target_value = 200, -- 200ms
            adjustment_factor = 1.1,
        },
        
        max_concurrent_jobs = {
            current = 3,
            min = 1,
            max = 8,
            target_metric = "queue_length",
            target_value = 5,
            adjustment_factor = 1.5,
        },
        
        cleanup_interval = {
            current = 30000, -- 30 seconds
            min = 5000,      -- 5 seconds
            max = 120000,    -- 2 minutes
            target_metric = "memory_usage_pct",
            target_value = 70, -- 70%
            adjustment_factor = 1.3,
        },
        
        debounce_delay = {
            current = 150, -- 150ms
            min = 50,      -- 50ms
            max = 1000,    -- 1 second
            target_metric = "completion_frequency",
            target_value = 10, -- requests per second
            adjustment_factor = 1.2,
        },
    },
    
    -- Metrics history for learning
    metrics_history = {},
    max_history_size = 100,
    
    -- Learning state
    learning_state = {
        iteration = 0,
        last_adjustment = {},
        performance_trend = {},
        stability_counter = {},
    },
    
    -- Tuning strategies
    strategies = {
        gradient_descent = true,
        adaptive_learning = true,
        momentum = true,
        early_stopping = true,
    },
    
    -- Performance thresholds
    thresholds = {
        min_improvement = 0.05, -- 5% minimum improvement
        stability_threshold = 10, -- 10 iterations without change
        performance_degradation = 0.1, -- 10% degradation trigger
    },
}

-- Dependencies
local performance = require("pebble.completion.performance")
local cache = require("pebble.completion.cache")
local async = require("pebble.completion.async")

-- Utility functions
local function clamp(value, min_val, max_val)
    return math.max(min_val, math.min(max_val, value))
end

local function moving_average(values, window_size)
    window_size = window_size or math.min(10, #values)
    if #values == 0 then return 0 end
    
    local start_idx = math.max(1, #values - window_size + 1)
    local sum = 0
    local count = 0
    
    for i = start_idx, #values do
        sum = sum + values[i]
        count = count + 1
    end
    
    return count > 0 and (sum / count) or 0
end

local function calculate_performance_score()
    local metrics = performance.get_metrics()
    local cache_stats = cache.get_stats()
    local async_stats = async.get_stats()
    
    -- Normalize metrics to 0-1 scale and calculate weighted score
    local weights = {
        completion_time = 0.3,
        cache_hit_rate = 0.25,
        memory_efficiency = 0.2,
        queue_performance = 0.15,
        error_rate = 0.1,
    }
    
    local scores = {}
    
    -- Completion time score (lower is better)
    local max_acceptable_time = 500 -- 500ms
    scores.completion_time = math.max(0, 1 - (metrics.completion_avg_time / max_acceptable_time))
    
    -- Cache hit rate score (higher is better)
    scores.cache_hit_rate = metrics.cache_hit_rate or 0
    
    -- Memory efficiency score (lower usage is better up to a point)
    local optimal_memory_usage = 0.6 -- 60% is optimal
    local memory_usage_pct = (metrics.cache_memory_usage or 0) / (100 * 1024 * 1024) -- Assume 100MB max
    scores.memory_efficiency = 1 - math.abs(memory_usage_pct - optimal_memory_usage) / optimal_memory_usage
    
    -- Queue performance score (fewer queued jobs is better)
    local max_acceptable_queue = 20
    scores.queue_performance = math.max(0, 1 - ((async_stats.queued_jobs or 0) / max_acceptable_queue))
    
    -- Error rate score (lower is better)
    scores.error_rate = 1 - (metrics.error_rate or 0)
    
    -- Calculate weighted score
    local total_score = 0
    for metric, weight in pairs(weights) do
        total_score = total_score + (scores[metric] * weight)
    end
    
    return total_score, scores
end

local function record_metrics(score, component_scores)
    local timestamp = vim.loop.now()
    
    table.insert(auto_tune.metrics_history, {
        timestamp = timestamp,
        score = score,
        components = component_scores,
        parameters = vim.deepcopy(auto_tune.parameters),
    })
    
    -- Limit history size
    if #auto_tune.metrics_history > auto_tune.max_history_size then
        table.remove(auto_tune.metrics_history, 1)
    end
end

-- Gradient-based parameter adjustment
local function adjust_parameter_gradient(param_name, param_config, current_score, historical_scores)
    if #historical_scores < 2 then
        return param_config.current -- Not enough data
    end
    
    -- Calculate gradient
    local recent_scores = {}
    for i = math.max(1, #historical_scores - 5), #historical_scores do
        table.insert(recent_scores, historical_scores[i])
    end
    
    local gradient = 0
    if #recent_scores >= 2 then
        gradient = recent_scores[#recent_scores] - recent_scores[#recent_scores - 1]
    end
    
    -- Determine adjustment direction based on gradient and target
    local adjustment = 0
    local current_value = param_config.current
    local target_reached = false
    
    if param_config.target_metric == "cache_hit_rate" then
        target_reached = current_score > param_config.target_value
    elseif param_config.target_metric == "avg_completion_time" then
        local current_time = performance.get_metrics().completion_avg_time or 0
        target_reached = current_time < param_config.target_value
    elseif param_config.target_metric == "memory_usage_pct" then
        local memory_pct = (performance.get_metrics().cache_memory_usage or 0) / (100 * 1024 * 1024) * 100
        target_reached = memory_pct < param_config.target_value
    elseif param_config.target_metric == "queue_length" then
        local queue_length = async.get_stats().queued_jobs or 0
        target_reached = queue_length < param_config.target_value
    end
    
    if not target_reached then
        if gradient > 0 then
            -- Performance is improving, continue in same direction
            adjustment = param_config.adjustment_factor
        else
            -- Performance is degrading, reverse direction
            adjustment = 1 / param_config.adjustment_factor
        end
    else
        -- Target reached, make smaller adjustments for stability
        adjustment = gradient > 0 and 1.05 or 0.95
    end
    
    local new_value = current_value * adjustment
    return clamp(new_value, param_config.min, param_config.max)
end

-- Adaptive learning rate adjustment
local function update_learning_rate(param_name, performance_trend)
    local base_rate = auto_tune.learning_rate
    
    if not performance_trend or #performance_trend < 3 then
        return base_rate
    end
    
    -- Calculate trend stability
    local trend_variance = 0
    local trend_mean = moving_average(performance_trend)
    
    for _, value in ipairs(performance_trend) do
        trend_variance = trend_variance + math.pow(value - trend_mean, 2)
    end
    trend_variance = trend_variance / #performance_trend
    
    -- Adjust learning rate based on stability
    local stability_factor = math.max(0.1, math.min(2.0, 1 / (1 + trend_variance)))
    return base_rate * stability_factor
end

-- Check for performance degradation and rollback if needed
local function check_and_rollback(param_name)
    local history = auto_tune.metrics_history
    if #history < 3 then return false end
    
    local recent_scores = {}
    for i = math.max(1, #history - 3), #history do
        table.insert(recent_scores, history[i].score)
    end
    
    local current_score = recent_scores[#recent_scores]
    local previous_score = recent_scores[#recent_scores - 1]
    
    if (previous_score - current_score) / previous_score > auto_tune.thresholds.performance_degradation then
        -- Significant degradation detected, rollback
        if auto_tune.learning_state.last_adjustment[param_name] then
            local param_config = auto_tune.parameters[param_name]
            param_config.current = auto_tune.learning_state.last_adjustment[param_name].previous_value
            
            vim.notify("Auto-tune: Rolled back " .. param_name .. " due to performance degradation", 
                      vim.log.levels.DEBUG)
            return true
        end
    end
    
    return false
end

-- Main auto-tuning function
local function perform_auto_tuning()
    if not auto_tune.enabled then return end
    
    auto_tune.learning_state.iteration = auto_tune.learning_state.iteration + 1
    
    -- Calculate current performance score
    local current_score, component_scores = calculate_performance_score()
    record_metrics(current_score, component_scores)
    
    -- Extract historical scores for trend analysis
    local historical_scores = {}
    for _, entry in ipairs(auto_tune.metrics_history) do
        table.insert(historical_scores, entry.score)
    end
    
    -- Adjust each parameter
    for param_name, param_config in pairs(auto_tune.parameters) do
        -- Store current value for potential rollback
        auto_tune.learning_state.last_adjustment[param_name] = {
            previous_value = param_config.current,
            iteration = auto_tune.learning_state.iteration,
        }
        
        -- Check for degradation and rollback if needed
        if not check_and_rollback(param_name) then
            -- Calculate new parameter value
            local new_value = adjust_parameter_gradient(param_name, param_config, current_score, historical_scores)
            
            -- Apply change if it's significant enough
            local change_magnitude = math.abs(new_value - param_config.current) / param_config.current
            if change_magnitude > auto_tune.thresholds.min_improvement then
                param_config.current = new_value
                
                -- Apply the parameter change to the appropriate system
                apply_parameter_change(param_name, new_value)
                
                -- Update performance trend
                if not auto_tune.learning_state.performance_trend[param_name] then
                    auto_tune.learning_state.performance_trend[param_name] = {}
                end
                table.insert(auto_tune.learning_state.performance_trend[param_name], current_score)
                
                -- Reset stability counter
                auto_tune.learning_state.stability_counter[param_name] = 0
            else
                -- No significant change, increment stability counter
                auto_tune.learning_state.stability_counter[param_name] = 
                    (auto_tune.learning_state.stability_counter[param_name] or 0) + 1
            end
        end
    end
end

-- Apply parameter changes to the actual systems
function apply_parameter_change(param_name, new_value)
    if param_name == "cache_ttl" then
        cache.configure(nil, {default_ttl = new_value})
        
    elseif param_name == "batch_size" then
        -- This would be applied to the completion system
        -- For now, store it for the completion system to read
        auto_tune.current_batch_size = new_value
        
    elseif param_name == "max_concurrent_jobs" then
        async.setup({max_concurrent_jobs = new_value})
        
    elseif param_name == "cleanup_interval" then
        cache.configure(nil, {cleanup_interval = new_value})
        
    elseif param_name == "debounce_delay" then
        -- This would be applied to the debounced completion triggers
        auto_tune.current_debounce_delay = new_value
    end
end

-- Public API functions

-- Enable/disable auto-tuning
function M.set_enabled(enabled)
    auto_tune.enabled = enabled
    return auto_tune.enabled
end

-- Get current parameter values
function M.get_current_parameters()
    local current_params = {}
    for name, config in pairs(auto_tune.parameters) do
        current_params[name] = {
            current = config.current,
            min = config.min,
            max = config.max,
            target_metric = config.target_metric,
            target_value = config.target_value,
        }
    end
    return current_params
end

-- Get auto-tuning statistics
function M.get_stats()
    local performance_scores = {}
    for _, entry in ipairs(auto_tune.metrics_history) do
        table.insert(performance_scores, entry.score)
    end
    
    return {
        enabled = auto_tune.enabled,
        iteration = auto_tune.learning_state.iteration,
        current_performance_score = #performance_scores > 0 and performance_scores[#performance_scores] or 0,
        avg_performance_score = moving_average(performance_scores),
        parameter_changes = vim.tbl_count(auto_tune.learning_state.last_adjustment),
        stability_counters = auto_tune.learning_state.stability_counter,
        learning_rate = auto_tune.learning_rate,
    }
end

-- Manual trigger for auto-tuning
function M.trigger_tuning()
    perform_auto_tuning()
end

-- Reset auto-tuning state
function M.reset()
    auto_tune.learning_state = {
        iteration = 0,
        last_adjustment = {},
        performance_trend = {},
        stability_counter = {},
    }
    auto_tune.metrics_history = {}
end

-- Configure auto-tuning parameters
function M.configure(config)
    config = config or {}
    
    if config.enabled ~= nil then
        auto_tune.enabled = config.enabled
    end
    
    if config.learning_rate then
        auto_tune.learning_rate = config.learning_rate
    end
    
    if config.parameters then
        for param_name, param_config in pairs(config.parameters) do
            if auto_tune.parameters[param_name] then
                auto_tune.parameters[param_name] = vim.tbl_deep_extend("force", 
                    auto_tune.parameters[param_name], param_config)
            end
        end
    end
    
    if config.thresholds then
        auto_tune.thresholds = vim.tbl_deep_extend("force", auto_tune.thresholds, config.thresholds)
    end
end

-- Get parameter recommendation based on current system state
function M.get_recommendations()
    local current_score, component_scores = calculate_performance_score()
    local recommendations = {}
    
    -- Analyze component scores and suggest improvements
    if component_scores.completion_time < 0.7 then
        table.insert(recommendations, {
            type = "performance",
            parameter = "batch_size",
            action = "decrease",
            reason = "Completion time is slow",
            current_score = component_scores.completion_time,
        })
    end
    
    if component_scores.cache_hit_rate < 0.6 then
        table.insert(recommendations, {
            type = "caching",
            parameter = "cache_ttl",
            action = "increase",
            reason = "Cache hit rate is low",
            current_score = component_scores.cache_hit_rate,
        })
    end
    
    if component_scores.memory_efficiency < 0.6 then
        table.insert(recommendations, {
            type = "memory",
            parameter = "cleanup_interval",
            action = "decrease",
            reason = "Memory usage is inefficient",
            current_score = component_scores.memory_efficiency,
        })
    end
    
    if component_scores.queue_performance < 0.6 then
        table.insert(recommendations, {
            type = "concurrency",
            parameter = "max_concurrent_jobs",
            action = "increase",
            reason = "Queue performance is poor",
            current_score = component_scores.queue_performance,
        })
    end
    
    return recommendations
end

-- Performance health check with auto-tuning insights
function M.health_check()
    local stats = M.get_stats()
    local recommendations = M.get_recommendations()
    
    local health = {
        status = "healthy",
        score = stats.current_performance_score,
        issues = {},
        recommendations = {},
        auto_tune_active = auto_tune.enabled,
    }
    
    -- Determine health status based on performance score
    if stats.current_performance_score < 0.5 then
        health.status = "critical"
        table.insert(health.issues, "Performance score critically low: " .. 
                    math.floor(stats.current_performance_score * 100) .. "%")
    elseif stats.current_performance_score < 0.7 then
        health.status = "warning"
        table.insert(health.issues, "Performance score below optimal: " .. 
                    math.floor(stats.current_performance_score * 100) .. "%")
    end
    
    -- Add specific recommendations
    for _, rec in ipairs(recommendations) do
        table.insert(health.recommendations, 
            string.format("Consider %s %s (%s)", rec.action, rec.parameter, rec.reason))
    end
    
    -- Check if auto-tuning is working effectively
    if auto_tune.enabled and stats.iteration > 10 then
        local recent_scores = {}
        local history_start = math.max(1, #auto_tune.metrics_history - 5)
        for i = history_start, #auto_tune.metrics_history do
            table.insert(recent_scores, auto_tune.metrics_history[i].score)
        end
        
        local improvement = #recent_scores >= 2 and 
                           (recent_scores[#recent_scores] - recent_scores[1]) or 0
        
        if improvement < 0.01 then -- Less than 1% improvement
            table.insert(health.issues, "Auto-tuning showing minimal improvement")
            table.insert(health.recommendations, "Consider manual parameter adjustment or reset auto-tuning")
        end
    end
    
    return health
end

-- Setup auto-tuning system with periodic execution
function M.setup(config)
    M.configure(config or {})
    
    -- Start periodic auto-tuning
    if auto_tune.enabled then
        local tuning_interval = (config and config.tuning_interval) or 60000 -- 1 minute default
        
        local timer = vim.loop.new_timer()
        timer:start(tuning_interval, tuning_interval, vim.schedule_wrap(function()
            if auto_tune.enabled then
                perform_auto_tuning()
            end
        end))
        
        -- Store timer for cleanup
        auto_tune.timer = timer
    end
    
    return true
end

-- Cleanup auto-tuning system
function M.cleanup()
    if auto_tune.timer then
        auto_tune.timer:stop()
        auto_tune.timer:close()
        auto_tune.timer = nil
    end
    
    M.reset()
end

-- Export current state for analysis
function M.export_state()
    return {
        parameters = auto_tune.parameters,
        metrics_history = auto_tune.metrics_history,
        learning_state = auto_tune.learning_state,
        config = {
            enabled = auto_tune.enabled,
            learning_rate = auto_tune.learning_rate,
            strategies = auto_tune.strategies,
            thresholds = auto_tune.thresholds,
        },
        timestamp = vim.loop.now(),
    }
end

return M
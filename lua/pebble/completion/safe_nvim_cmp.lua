-- Safe nvim-cmp completion source with comprehensive error handling and timeout protection
local M = {}

-- Safety constants and configuration
local COMPLETION_TIMEOUT = 5000  -- 5 second timeout for completion operations
local MAX_COMPLETION_ITEMS = 100 -- Maximum items returned to prevent UI lag
local MAX_FILE_SCAN_COUNT = 1000 -- Limit file scanning for performance
local MAX_MEMORY_USAGE = 50 * 1024 * 1024 -- 50MB memory limit for completion data
local DEBOUNCE_DELAY = 100 -- Milliseconds to debounce completion requests
local MAX_RETRIES = 3 -- Maximum retry attempts for failed operations
local ERROR_COOLDOWN = 5000 -- Cooldown period after errors (ms)

-- Performance and resource tracking
local performance_stats = {
    completion_calls = 0,
    successful_completions = 0,
    failed_completions = 0,
    timeout_errors = 0,
    memory_errors = 0,
    last_error_time = 0,
    avg_completion_time = 0,
    total_completion_time = 0,
}

-- Error tracking and circuit breaker
local error_tracker = {
    consecutive_errors = 0,
    last_error_time = 0,
    is_circuit_open = false,
    error_types = {},
}

-- Request management for timeout and debouncing
local active_requests = {}
local request_counter = 0
local last_request_time = 0

-- Safe wrapper for all operations with timeout
local function safe_call_with_timeout(operation, timeout_ms, callback)
    timeout_ms = timeout_ms or COMPLETION_TIMEOUT
    local request_id = request_counter + 1
    request_counter = request_id
    
    -- Store active request for cleanup
    active_requests[request_id] = {
        start_time = vim.loop.now(),
        timeout = timeout_ms,
        completed = false,
    }
    
    -- Timeout timer
    local timeout_timer = vim.defer_fn(function()
        if active_requests[request_id] and not active_requests[request_id].completed then
            active_requests[request_id].completed = true
            active_requests[request_id] = nil
            
            performance_stats.timeout_errors = performance_stats.timeout_errors + 1
            error_tracker.consecutive_errors = error_tracker.consecutive_errors + 1
            error_tracker.last_error_time = vim.loop.now()
            
            if callback then
                callback(nil, "Operation timed out after " .. timeout_ms .. "ms")
            end
        end
    end, timeout_ms)
    
    -- Execute operation with error handling
    local success, result = xpcall(function()
        return operation()
    end, function(err)
        -- Enhanced error reporting with stack trace
        local error_info = {
            message = tostring(err),
            stack = debug.traceback(err, 2),
            timestamp = vim.loop.now(),
            request_id = request_id,
        }
        return error_info
    end)
    
    -- Handle completion
    local function complete_request(result, error)
        if active_requests[request_id] and not active_requests[request_id].completed then
            active_requests[request_id].completed = true
            
            -- Calculate completion time
            local completion_time = vim.loop.now() - active_requests[request_id].start_time
            performance_stats.total_completion_time = performance_stats.total_completion_time + completion_time
            performance_stats.completion_calls = performance_stats.completion_calls + 1
            performance_stats.avg_completion_time = performance_stats.total_completion_time / performance_stats.completion_calls
            
            active_requests[request_id] = nil
            
            -- Cancel timeout timer
            if timeout_timer then
                timeout_timer:close()
            end
            
            if callback then
                callback(result, error)
            end
        end
    end
    
    -- Handle result
    if success then
        if type(result) == "function" then
            -- Async operation - wrap callback
            result(function(async_result, async_error)
                if async_error then
                    performance_stats.failed_completions = performance_stats.failed_completions + 1
                    error_tracker.consecutive_errors = error_tracker.consecutive_errors + 1
                    error_tracker.last_error_time = vim.loop.now()
                else
                    performance_stats.successful_completions = performance_stats.successful_completions + 1
                    error_tracker.consecutive_errors = 0
                end
                complete_request(async_result, async_error)
            end)
        else
            -- Sync operation
            performance_stats.successful_completions = performance_stats.successful_completions + 1
            error_tracker.consecutive_errors = 0
            complete_request(result, nil)
        end
    else
        -- Operation failed
        performance_stats.failed_completions = performance_stats.failed_completions + 1
        error_tracker.consecutive_errors = error_tracker.consecutive_errors + 1
        error_tracker.last_error_time = vim.loop.now()
        
        -- Track error type
        if result and result.message then
            local error_type = result.message:match("^([^:]+)") or "unknown"
            error_tracker.error_types[error_type] = (error_tracker.error_types[error_type] or 0) + 1
        end
        
        complete_request(nil, result)
    end
end

-- Circuit breaker implementation
local function is_circuit_breaker_open()
    local now = vim.loop.now()
    
    -- Open circuit if too many consecutive errors
    if error_tracker.consecutive_errors >= 5 then
        error_tracker.is_circuit_open = true
        return true
    end
    
    -- Keep circuit open for cooldown period after errors
    if error_tracker.is_circuit_open and (now - error_tracker.last_error_time) < ERROR_COOLDOWN then
        return true
    end
    
    -- Reset circuit breaker
    if error_tracker.is_circuit_open and (now - error_tracker.last_error_time) >= ERROR_COOLDOWN then
        error_tracker.is_circuit_open = false
        error_tracker.consecutive_errors = 0
    end
    
    return false
end

-- Memory usage monitoring
local function check_memory_usage()
    -- Get Lua memory usage (in KB)
    local memory_kb = collectgarbage("count")
    local memory_bytes = memory_kb * 1024
    
    if memory_bytes > MAX_MEMORY_USAGE then
        -- Force garbage collection
        collectgarbage("collect")
        
        -- Check again after GC
        memory_kb = collectgarbage("count")
        memory_bytes = memory_kb * 1024
        
        if memory_bytes > MAX_MEMORY_USAGE then
            performance_stats.memory_errors = performance_stats.memory_errors + 1
            return false, "Memory usage too high: " .. math.floor(memory_kb) .. "KB"
        end
    end
    
    return true, memory_kb
end

-- Safe completion wrapper
local function get_safe_completions(context, callback)
    -- Check circuit breaker
    if is_circuit_breaker_open() then
        callback({ items = {}, isIncomplete = false }, "Circuit breaker is open due to recent errors")
        return
    end
    
    -- Check memory usage
    local memory_ok, memory_info = check_memory_usage()
    if not memory_ok then
        callback({ items = {}, isIncomplete = false }, memory_info)
        return
    end
    
    -- Debounce rapid requests
    local now = vim.loop.now()
    if (now - last_request_time) < DEBOUNCE_DELAY then
        -- Schedule debounced request
        vim.defer_fn(function()
            get_safe_completions(context, callback)
        end, DEBOUNCE_DELAY)
        return
    end
    last_request_time = now
    
    -- Safe completion operation
    safe_call_with_timeout(function()
        return function(completion_callback)
            -- Use existing completion module with safety wrapper
            local completion_module = require("pebble.completion")
            
            -- Validate context parameters
            if not context or not context.cursor_line or not context.cursor then
                completion_callback({ items = {}, isIncomplete = false }, nil)
                return
            end
            
            local line = context.cursor_line
            local col = context.cursor.col or context.cursor.character or 0
            
            -- Limit line length for safety
            if #line > 10000 then
                line = line:sub(1, 10000)
            end
            
            -- Get completions with resource limits
            local success, items_or_error = pcall(function()
                return completion_module.get_completions_for_context(line, col)
            end)
            
            if not success then
                completion_callback({ items = {}, isIncomplete = false }, items_or_error)
                return
            end
            
            local items = items_or_error or {}
            
            -- Apply safety limits
            if #items > MAX_COMPLETION_ITEMS then
                items = vim.list_slice(items, 1, MAX_COMPLETION_ITEMS)
            end
            
            -- Validate and sanitize items
            local safe_items = {}
            for i, item in ipairs(items) do
                if i > MAX_COMPLETION_ITEMS then break end
                
                if type(item) == "table" and item.label then
                    -- Sanitize item properties
                    local safe_item = {
                        label = tostring(item.label):sub(1, 200), -- Limit label length
                        kind = type(item.kind) == "number" and item.kind or 1,
                        detail = item.detail and tostring(item.detail):sub(1, 500) or nil,
                        insertText = item.insertText and tostring(item.insertText):sub(1, 500) or item.label,
                        filterText = item.filterText and tostring(item.filterText):sub(1, 200) or nil,
                        sortText = item.sortText and tostring(item.sortText):sub(1, 100) or nil,
                        documentation = item.documentation,
                        textEdit = item.textEdit,
                        data = item.data,
                    }
                    
                    -- Validate documentation
                    if safe_item.documentation and type(safe_item.documentation) == "table" then
                        if safe_item.documentation.value then
                            safe_item.documentation.value = tostring(safe_item.documentation.value):sub(1, 2000)
                        end
                    end
                    
                    table.insert(safe_items, safe_item)
                end
            end
            
            completion_callback({
                items = safe_items,
                isIncomplete = #items > MAX_COMPLETION_ITEMS
            }, nil)
        end
    end, COMPLETION_TIMEOUT, callback)
end

-- Enhanced completion source implementation
local source = {}

function M.is_available()
    local ok, cmp = pcall(require, "cmp")
    return ok and cmp ~= nil
end

function M.register(opts)
    opts = opts or {}
    
    if not M.is_available() then
        return false, "nvim-cmp not available"
    end

    local cmp = require("cmp")
    
    -- Enhanced source configuration
    source.opts = vim.tbl_deep_extend("force", {
        name = "pebble_safe",
        priority = opts.priority or 100,
        max_item_count = math.min(opts.max_item_count or 50, MAX_COMPLETION_ITEMS),
        trigger_characters = opts.trigger_characters or { "[", "(" },
        keyword_pattern = opts.keyword_pattern or [[\k\+]],
        keyword_length = opts.keyword_length or 0,
        -- Safety options
        enable_timeout = opts.enable_timeout ~= false,
        timeout_ms = opts.timeout_ms or COMPLETION_TIMEOUT,
        enable_memory_check = opts.enable_memory_check ~= false,
        enable_circuit_breaker = opts.enable_circuit_breaker ~= false,
    }, opts)

    -- Register the safe source
    local success, error_msg = pcall(function()
        cmp.register_source("pebble_safe", source)
    end)
    
    if not success then
        return false, "Failed to register source: " .. (error_msg or "unknown error")
    end
    
    return true, "Source registered successfully"
end

-- Source implementation with safety measures
function source:get_trigger_characters()
    return self.opts.trigger_characters or {}
end

function source:get_keyword_pattern()
    return self.opts.keyword_pattern or [[\k\+]]
end

function source:is_available()
    -- Circuit breaker check
    if self.opts.enable_circuit_breaker and is_circuit_breaker_open() then
        return false
    end
    
    -- Memory check
    if self.opts.enable_memory_check then
        local memory_ok = check_memory_usage()
        if not memory_ok then
            return false
        end
    end
    
    -- Basic availability check
    local success, result = pcall(function()
        local completion = require("pebble.completion")
        return completion.is_completion_enabled()
    end)
    
    return success and result
end

function source:complete(request, callback)
    -- Validate request
    if not request or not request.context then
        callback({ items = {}, isIncomplete = false })
        return
    end
    
    -- Enhanced context validation
    local context = request.context
    if not context.cursor_line or not context.cursor then
        callback({ items = {}, isIncomplete = false })
        return
    end
    
    -- Check if completion should be triggered
    local line = context.cursor_line
    local col = context.cursor.col or context.cursor.character or 0
    
    -- Safety check for line length and column position
    if #line > 50000 or col < 0 or col > #line + 100 then
        callback({ items = {}, isIncomplete = false })
        return
    end
    
    -- Context-aware triggering
    local should_complete = false
    
    -- Safe substring extraction
    local safe_start = math.max(1, col - 10)
    local safe_end = math.min(#line, col + 5)
    local context_snippet = line:sub(safe_start, safe_end)
    
    -- Check for wiki links [[
    if context_snippet:find("%[%[") then
        should_complete = true
    end
    
    -- Check for markdown links ](
    if context_snippet:find("%]%(") then
        should_complete = true
    end
    
    -- Additional context checks with error handling
    if not should_complete then
        local check_success, is_wiki, is_markdown = pcall(function()
            local completion = require("pebble.completion")
            local wiki_context, _ = completion.is_wiki_link_context()
            local md_context, _ = completion.is_markdown_link_context()
            return wiki_context, md_context
        end)
        
        if check_success and (is_wiki or is_markdown) then
            should_complete = true
        end
    end
    
    -- Return early if no completion context
    if not should_complete then
        callback({ items = {}, isIncomplete = false })
        return
    end
    
    -- Get safe completions with timeout and error handling
    get_safe_completions(context, function(result, error)
        if error then
            -- Log error but don't crash
            vim.schedule(function()
                vim.notify("Pebble completion error: " .. tostring(error), vim.log.levels.DEBUG)
            end)
            callback({ items = {}, isIncomplete = false })
        else
            -- Limit results based on source configuration
            local items = result.items or {}
            if #items > source.opts.max_item_count then
                items = vim.list_slice(items, 1, source.opts.max_item_count)
            end
            
            -- Add source metadata
            for _, item in ipairs(items) do
                item.data = item.data or {}
                item.data.source = "pebble_safe"
                item.data.request_id = request_counter
            end
            
            callback({
                items = items,
                isIncomplete = result.isIncomplete or #result.items > source.opts.max_item_count
            })
        end
    end)
end

function source:resolve(completion_item, callback)
    -- Safe resolution with timeout
    safe_call_with_timeout(function()
        return function(resolve_callback)
            -- Enhanced documentation with safety info
            local data = completion_item.data or {}
            
            if data.type == "wiki_link" then
                completion_item.documentation = {
                    kind = "markdown",
                    value = string.format(
                        "**Wiki Link**: `[[%s]]`\n\n**File**: %s\n\n*Safe completion with timeout protection*",
                        completion_item.label or "",
                        data.relative_path or data.file_path or "unknown"
                    )
                }
            elseif data.type == "file_path" then
                completion_item.documentation = {
                    kind = "markdown",
                    value = string.format(
                        "**Markdown Link**: `[text](%s)`\n\n**File**: %s\n\n*Safe completion with error handling*",
                        completion_item.insertText or "",
                        data.relative_path or data.file_path or "unknown"
                    )
                }
            end
            
            resolve_callback(completion_item, nil)
        end
    end, 1000, function(result, error) -- Shorter timeout for resolve
        if error then
            vim.schedule(function()
                vim.notify("Pebble resolve error: " .. tostring(error), vim.log.levels.DEBUG)
            end)
        end
        callback(result or completion_item)
    end)
end

function source:execute(completion_item, callback)
    -- Safe execution
    safe_call_with_timeout(function()
        return function(execute_callback)
            -- Could add post-completion actions here
            execute_callback(completion_item, nil)
        end
    end, 500, function(result, error) -- Very short timeout for execute
        if error then
            vim.schedule(function()
                vim.notify("Pebble execute error: " .. tostring(error), vim.log.levels.DEBUG)
            end)
        end
        callback(result or completion_item)
    end)
end

-- Cleanup and resource management
function M.cleanup()
    -- Clear active requests
    for request_id, _ in pairs(active_requests) do
        if active_requests[request_id] then
            active_requests[request_id].completed = true
        end
    end
    active_requests = {}
    
    -- Reset performance stats
    performance_stats = {
        completion_calls = 0,
        successful_completions = 0,
        failed_completions = 0,
        timeout_errors = 0,
        memory_errors = 0,
        last_error_time = 0,
        avg_completion_time = 0,
        total_completion_time = 0,
    }
    
    -- Reset error tracker
    error_tracker = {
        consecutive_errors = 0,
        last_error_time = 0,
        is_circuit_open = false,
        error_types = {},
    }
    
    -- Force garbage collection
    collectgarbage("collect")
end

-- Performance monitoring
function M.get_performance_stats()
    local stats = vim.deepcopy(performance_stats)
    
    -- Add current memory usage
    local memory_kb = collectgarbage("count")
    stats.current_memory_kb = memory_kb
    stats.current_memory_mb = math.floor(memory_kb / 1024 * 100) / 100
    
    -- Add active request count
    stats.active_requests = vim.tbl_count(active_requests)
    
    -- Add error information
    stats.error_tracker = vim.deepcopy(error_tracker)
    
    -- Calculate success rate
    if stats.completion_calls > 0 then
        stats.success_rate = (stats.successful_completions / stats.completion_calls) * 100
    else
        stats.success_rate = 0
    end
    
    return stats
end

-- Health check function
function M.health_check()
    local health = {
        overall_status = "healthy",
        issues = {},
        recommendations = {},
    }
    
    -- Check circuit breaker status
    if is_circuit_breaker_open() then
        health.overall_status = "degraded"
        table.insert(health.issues, "Circuit breaker is open due to recent errors")
        table.insert(health.recommendations, "Check error logs and consider restarting completion system")
    end
    
    -- Check memory usage
    local memory_ok, memory_info = check_memory_usage()
    if not memory_ok then
        health.overall_status = "critical"
        table.insert(health.issues, memory_info)
        table.insert(health.recommendations, "Reduce completion cache size or restart Neovim")
    end
    
    -- Check performance stats
    local stats = M.get_performance_stats()
    if stats.success_rate < 80 and stats.completion_calls > 10 then
        health.overall_status = "degraded"
        table.insert(health.issues, "Low completion success rate: " .. math.floor(stats.success_rate) .. "%")
        table.insert(health.recommendations, "Check completion configuration and file accessibility")
    end
    
    if stats.avg_completion_time > 2000 then
        health.overall_status = "degraded"
        table.insert(health.issues, "High average completion time: " .. math.floor(stats.avg_completion_time) .. "ms")
        table.insert(health.recommendations, "Consider reducing file scan limits or using faster storage")
    end
    
    -- Add performance info
    health.performance = stats
    
    return health
end

return M
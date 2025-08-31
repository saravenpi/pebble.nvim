local M = {}

-- Async processing system with timeout protection, queue management, and progress tracking
local async = {
    jobs = {}, -- Active jobs
    queue = {}, -- Job queue
    config = {
        max_concurrent_jobs = 3,
        default_timeout = 5000, -- 5 seconds
        queue_max_size = 100,
        retry_count = 2,
        retry_delay = 1000, -- 1 second
        progress_callback = nil,
    },
    stats = {
        jobs_completed = 0,
        jobs_failed = 0,
        jobs_timeout = 0,
        jobs_cancelled = 0,
        avg_execution_time = 0,
    },
    job_id_counter = 0,
}

-- Performance monitoring integration
local performance = require("pebble.completion.performance")

-- Job states
local JOB_STATES = {
    PENDING = "pending",
    RUNNING = "running", 
    COMPLETED = "completed",
    FAILED = "failed",
    TIMEOUT = "timeout",
    CANCELLED = "cancelled",
}

-- Create a new job
local function create_job(task_func, options)
    options = options or {}
    async.job_id_counter = async.job_id_counter + 1
    
    return {
        id = async.job_id_counter,
        task_func = task_func,
        state = JOB_STATES.PENDING,
        created_at = vim.loop.now(),
        started_at = nil,
        completed_at = nil,
        timeout = options.timeout or async.config.default_timeout,
        retries_left = options.retries or async.config.retry_count,
        priority = options.priority or 0, -- Higher numbers = higher priority
        tags = options.tags or {},
        callback = options.callback,
        error_callback = options.error_callback,
        progress_callback = options.progress_callback,
        timer = nil,
        result = nil,
        error = nil,
    }
end

-- Progress tracking utilities
local function create_progress_tracker(job_id, total_steps)
    local progress = {
        job_id = job_id,
        current_step = 0,
        total_steps = total_steps or 100,
        message = "",
        start_time = vim.loop.now(),
        last_update = vim.loop.now(),
    }
    
    local function update_progress(step, message)
        progress.current_step = step or progress.current_step + 1
        progress.message = message or progress.message
        progress.last_update = vim.loop.now()
        
        local job = async.jobs[job_id]
        if job and job.progress_callback then
            vim.schedule(function()
                job.progress_callback(progress)
            end)
        end
        
        -- Global progress callback
        if async.config.progress_callback then
            vim.schedule(function()
                async.config.progress_callback(job_id, progress)
            end)
        end
    end
    
    local function complete_progress(message)
        update_progress(progress.total_steps, message or "Completed")
    end
    
    return {
        update = update_progress,
        complete = complete_progress,
        get = function() return progress end
    }
end

-- Execute job with timeout protection
local function execute_job(job)
    job.state = JOB_STATES.RUNNING
    job.started_at = vim.loop.now()
    
    -- Setup timeout timer
    job.timer = vim.loop.new_timer()
    job.timer:start(job.timeout, 0, function()
        if job.state == JOB_STATES.RUNNING then
            job.state = JOB_STATES.TIMEOUT
            job.completed_at = vim.loop.now()
            job.error = "Job timed out after " .. job.timeout .. "ms"
            
            async.stats.jobs_timeout = async.stats.jobs_timeout + 1
            performance.record_timeout("async_job")
            
            vim.schedule(function()
                if job.error_callback then
                    job.error_callback(job.error, job)
                end
                finish_job(job)
            end)
        end
    end)
    
    -- Create progress tracker for the job
    local progress = create_progress_tracker(job.id)
    
    -- Execute the task
    local function execute_with_protection()
        local ok, result = pcall(job.task_func, progress)
        
        -- Clean up timer
        if job.timer then
            job.timer:stop()
            job.timer:close()
            job.timer = nil
        end
        
        if job.state == JOB_STATES.TIMEOUT then
            -- Job already timed out
            return
        end
        
        job.completed_at = vim.loop.now()
        local execution_time = job.completed_at - job.started_at
        
        if ok then
            job.state = JOB_STATES.COMPLETED
            job.result = result
            async.stats.jobs_completed = async.stats.jobs_completed + 1
            
            -- Update average execution time
            local total_jobs = async.stats.jobs_completed
            async.stats.avg_execution_time = 
                ((async.stats.avg_execution_time * (total_jobs - 1)) + execution_time) / total_jobs
            
            vim.schedule(function()
                if job.callback then
                    job.callback(result, job)
                end
                finish_job(job)
            end)
        else
            job.state = JOB_STATES.FAILED
            job.error = result -- pcall returns error as second return value on failure
            
            -- Retry if retries left
            if job.retries_left > 0 then
                job.retries_left = job.retries_left - 1
                job.state = JOB_STATES.PENDING
                
                -- Schedule retry after delay
                vim.defer_fn(function()
                    queue_job(job)
                end, async.config.retry_delay)
            else
                async.stats.jobs_failed = async.stats.jobs_failed + 1
                
                vim.schedule(function()
                    if job.error_callback then
                        job.error_callback(job.error, job)
                    end
                    finish_job(job)
                end)
            end
        end
    end
    
    -- Execute in next tick to avoid blocking
    vim.schedule(execute_with_protection)
end

-- Finish job and clean up
local function finish_job(job)
    async.jobs[job.id] = nil
    process_queue()
end

-- Add job to queue
local function queue_job(job)
    -- Check queue size limit
    if #async.queue >= async.config.queue_max_size then
        -- Remove oldest low-priority job
        local removed = false
        for i = #async.queue, 1, -1 do
            if async.queue[i].priority <= job.priority then
                table.remove(async.queue, i)
                removed = true
                break
            end
        end
        
        if not removed then
            -- Queue is full with higher priority jobs
            job.state = JOB_STATES.CANCELLED
            async.stats.jobs_cancelled = async.stats.jobs_cancelled + 1
            
            if job.error_callback then
                vim.schedule(function()
                    job.error_callback("Queue full", job)
                end)
            end
            return false
        end
    end
    
    table.insert(async.queue, job)
    
    -- Sort queue by priority (highest first)
    table.sort(async.queue, function(a, b)
        return a.priority > b.priority
    end)
    
    process_queue()
    return true
end

-- Process job queue
function process_queue()
    local concurrent_count = vim.tbl_count(async.jobs)
    
    -- Start jobs up to the concurrent limit
    while concurrent_count < async.config.max_concurrent_jobs and #async.queue > 0 do
        local job = table.remove(async.queue, 1) -- Take highest priority job
        async.jobs[job.id] = job
        execute_job(job)
        concurrent_count = concurrent_count + 1
    end
end

-- Public API functions

-- Run async task with options
function M.run(task_func, options)
    options = options or {}
    local job = create_job(task_func, options)
    
    if queue_job(job) then
        return job.id
    else
        return nil
    end
end

-- Run multiple tasks in parallel with optional concurrency limit
function M.parallel(tasks, options)
    options = options or {}
    local max_parallel = options.max_parallel or async.config.max_concurrent_jobs
    local results = {}
    local errors = {}
    local completed_count = 0
    local total_count = #tasks
    
    local function on_task_complete(task_id, success, result)
        completed_count = completed_count + 1
        
        if success then
            results[task_id] = result
        else
            errors[task_id] = result
        end
        
        if completed_count == total_count then
            if options.callback then
                options.callback(results, errors)
            end
        end
    end
    
    -- Start tasks with controlled concurrency
    local job_ids = {}
    for i, task in ipairs(tasks) do
        local job_id = M.run(task, {
            timeout = options.timeout,
            priority = options.priority,
            callback = function(result, job)
                on_task_complete(i, true, result)
            end,
            error_callback = function(error, job)
                on_task_complete(i, false, error)
            end,
        })
        
        if job_id then
            job_ids[i] = job_id
        end
    end
    
    return job_ids
end

-- Run tasks in sequence (one after another)
function M.sequence(tasks, options)
    options = options or {}
    local results = {}
    local current_index = 1
    
    local function run_next()
        if current_index > #tasks then
            if options.callback then
                options.callback(results)
            end
            return
        end
        
        local task = tasks[current_index]
        M.run(task, {
            timeout = options.timeout,
            priority = options.priority,
            callback = function(result, job)
                results[current_index] = result
                current_index = current_index + 1
                run_next()
            end,
            error_callback = function(error, job)
                if options.error_callback then
                    options.error_callback(error, current_index)
                end
                -- Continue with next task unless stop_on_error is true
                if not options.stop_on_error then
                    results[current_index] = nil
                    current_index = current_index + 1
                    run_next()
                end
            end,
        })
    end
    
    run_next()
end

-- Debounced execution - delays execution until after wait period
function M.debounce(func, wait, options)
    options = options or {}
    local timer = nil
    local last_args = nil
    
    return function(...)
        last_args = {...}
        
        if timer then
            timer:stop()
            timer:close()
        end
        
        timer = vim.loop.new_timer()
        timer:start(wait, 0, function()
            timer:stop()
            timer:close()
            timer = nil
            
            vim.schedule(function()
                M.run(function()
                    return func(unpack(last_args))
                end, options)
            end)
        end)
    end
end

-- Throttled execution - limits execution rate
function M.throttle(func, limit, options)
    options = options or {}
    local last_execution = 0
    local pending_args = nil
    local timer = nil
    
    return function(...)
        local now = vim.loop.now()
        local time_since_last = now - last_execution
        
        pending_args = {...}
        
        if time_since_last >= limit then
            -- Execute immediately
            last_execution = now
            M.run(function()
                return func(unpack(pending_args))
            end, options)
        else
            -- Schedule execution
            if timer then
                timer:stop()
                timer:close()
            end
            
            local delay = limit - time_since_last
            timer = vim.loop.new_timer()
            timer:start(delay, 0, function()
                timer:stop()
                timer:close()
                timer = nil
                last_execution = vim.loop.now()
                
                vim.schedule(function()
                    M.run(function()
                        return func(unpack(pending_args))
                    end, options)
                end)
            end)
        end
    end
end

-- Cancel job by ID
function M.cancel(job_id)
    -- Check if job is in queue
    for i, job in ipairs(async.queue) do
        if job.id == job_id then
            table.remove(async.queue, i)
            job.state = JOB_STATES.CANCELLED
            async.stats.jobs_cancelled = async.stats.jobs_cancelled + 1
            
            if job.error_callback then
                vim.schedule(function()
                    job.error_callback("Cancelled", job)
                end)
            end
            return true
        end
    end
    
    -- Check if job is running
    local job = async.jobs[job_id]
    if job then
        job.state = JOB_STATES.CANCELLED
        async.stats.jobs_cancelled = async.stats.jobs_cancelled + 1
        
        if job.timer then
            job.timer:stop()
            job.timer:close()
            job.timer = nil
        end
        
        if job.error_callback then
            vim.schedule(function()
                job.error_callback("Cancelled", job)
            end)
        end
        
        finish_job(job)
        return true
    end
    
    return false
end

-- Cancel all jobs with optional tag filter
function M.cancel_all(tag_filter)
    local cancelled_count = 0
    
    -- Cancel queued jobs
    for i = #async.queue, 1, -1 do
        local job = async.queue[i]
        local should_cancel = not tag_filter or vim.tbl_contains(job.tags, tag_filter)
        
        if should_cancel then
            table.remove(async.queue, i)
            job.state = JOB_STATES.CANCELLED
            cancelled_count = cancelled_count + 1
            
            if job.error_callback then
                vim.schedule(function()
                    job.error_callback("Cancelled", job)
                end)
            end
        end
    end
    
    -- Cancel running jobs
    for job_id, job in pairs(async.jobs) do
        local should_cancel = not tag_filter or vim.tbl_contains(job.tags, tag_filter)
        
        if should_cancel then
            M.cancel(job_id)
            cancelled_count = cancelled_count + 1
        end
    end
    
    async.stats.jobs_cancelled = async.stats.jobs_cancelled + cancelled_count
    return cancelled_count
end

-- Get job status
function M.get_job_status(job_id)
    -- Check running jobs
    local job = async.jobs[job_id]
    if job then
        return {
            id = job.id,
            state = job.state,
            created_at = job.created_at,
            started_at = job.started_at,
            completed_at = job.completed_at,
            elapsed_time = job.started_at and (vim.loop.now() - job.started_at) or 0,
            retries_left = job.retries_left,
            tags = job.tags,
        }
    end
    
    -- Check queued jobs
    for _, queued_job in ipairs(async.queue) do
        if queued_job.id == job_id then
            return {
                id = queued_job.id,
                state = queued_job.state,
                created_at = queued_job.created_at,
                queue_position = _,
                retries_left = queued_job.retries_left,
                tags = queued_job.tags,
            }
        end
    end
    
    return nil
end

-- Get system statistics
function M.get_stats()
    local queue_stats = {}
    local priority_count = {}
    
    for _, job in ipairs(async.queue) do
        priority_count[job.priority] = (priority_count[job.priority] or 0) + 1
    end
    
    return {
        running_jobs = vim.tbl_count(async.jobs),
        queued_jobs = #async.queue,
        completed_jobs = async.stats.jobs_completed,
        failed_jobs = async.stats.jobs_failed,
        timeout_jobs = async.stats.jobs_timeout,
        cancelled_jobs = async.stats.jobs_cancelled,
        avg_execution_time = async.stats.avg_execution_time,
        queue_priority_distribution = priority_count,
        config = async.config,
    }
end

-- Health check
function M.health_check()
    local stats = M.get_stats()
    local health = {
        status = "healthy",
        issues = {},
        recommendations = {},
    }
    
    -- Check queue size
    if stats.queued_jobs > async.config.queue_max_size * 0.8 then
        health.status = "warning"
        table.insert(health.issues, "Queue nearly full: " .. stats.queued_jobs .. "/" .. async.config.queue_max_size)
        table.insert(health.recommendations, "Consider increasing max_concurrent_jobs or queue_max_size")
    end
    
    -- Check failure rate
    local total_jobs = stats.completed_jobs + stats.failed_jobs + stats.timeout_jobs
    if total_jobs > 0 then
        local failure_rate = (stats.failed_jobs + stats.timeout_jobs) / total_jobs
        if failure_rate > 0.1 then
            health.status = "warning"
            table.insert(health.issues, "High failure rate: " .. math.floor(failure_rate * 100) .. "%")
            table.insert(health.recommendations, "Review timeout settings and error handling")
        end
    end
    
    -- Check average execution time
    if stats.avg_execution_time > async.config.default_timeout * 0.8 then
        health.status = "warning"
        table.insert(health.issues, "Jobs taking too long on average: " .. math.floor(stats.avg_execution_time) .. "ms")
        table.insert(health.recommendations, "Consider increasing timeout or optimizing task performance")
    end
    
    return health
end

-- Configure async system
function M.setup(config)
    config = config or {}
    async.config = vim.tbl_deep_extend("force", async.config, config)
    return true
end

-- Get current configuration
function M.get_config()
    return vim.deepcopy(async.config)
end

-- Cleanup and stop all jobs
function M.cleanup()
    -- Cancel all jobs
    M.cancel_all()
    
    -- Clean up any remaining timers
    for _, job in pairs(async.jobs) do
        if job.timer then
            job.timer:stop()
            job.timer:close()
        end
    end
    
    async.jobs = {}
    async.queue = {}
end

return M
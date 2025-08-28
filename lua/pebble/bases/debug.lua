local M = {}

-- Debug configuration
local DEBUG_ENABLED = false -- Set to true for debugging, false for production
local LOG_FILE = nil -- Set to a path like "/tmp/pebble-bases-debug.log" to enable file logging

-- Log levels
M.LOG_LEVELS = {
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    DEBUG = 4,
    TRACE = 5
}

local current_log_level = M.LOG_LEVELS.DEBUG

-- Internal state tracking
local function_call_stack = {}
local component_states = {
    cache = "unknown",
    parser = "unknown", 
    filters = "unknown",
    formulas = "unknown",
    views = "unknown"
}

-- Helper function to format log messages
local function format_log(level, component, message, data)
    local timestamp = os.date("%H:%M:%S")
    local level_str = ""
    for k, v in pairs(M.LOG_LEVELS) do
        if v == level then
            level_str = k
            break
        end
    end
    
    local log_line = string.format("[%s] [%s] %s: %s", timestamp, level_str, component, message)
    if data then
        local data_str = type(data) == "table" and vim.inspect(data) or tostring(data)
        log_line = log_line .. " | Data: " .. data_str
    end
    
    return log_line
end

-- Main logging function
local function log(level, component, message, data)
    if not DEBUG_ENABLED or level > current_log_level then
        return
    end
    
    local log_line = format_log(level, component, message, data)
    
    -- Print to Neovim
    if level <= M.LOG_LEVELS.WARN then
        vim.notify(log_line, vim.log.levels.WARN)
    else
        print(log_line)
    end
    
    -- Write to file if configured
    if LOG_FILE then
        local file = io.open(LOG_FILE, "a")
        if file then
            file:write(log_line .. "\n")
            file:close()
        end
    end
end

-- Public logging functions
function M.error(component, message, data)
    log(M.LOG_LEVELS.ERROR, component, message, data)
end

function M.warn(component, message, data)
    log(M.LOG_LEVELS.WARN, component, message, data)
end

function M.info(component, message, data)
    log(M.LOG_LEVELS.INFO, component, message, data)
end

function M.debug(component, message, data)
    log(M.LOG_LEVELS.DEBUG, component, message, data)
end

function M.trace(component, message, data)
    log(M.LOG_LEVELS.TRACE, component, message, data)
end

-- Function call tracking
function M.enter_function(component, func_name, args)
    local call_info = {
        component = component,
        func_name = func_name,
        args = args,
        start_time = vim.loop.hrtime()
    }
    table.insert(function_call_stack, call_info)
    
    M.trace(component, "ENTER " .. func_name, args)
end

function M.exit_function(component, func_name, result)
    local call_info = table.remove(function_call_stack)
    if call_info then
        local duration = (vim.loop.hrtime() - call_info.start_time) / 1000000 -- ms
        M.trace(component, "EXIT " .. func_name .. " (" .. math.floor(duration) .. "ms)", result)
    end
end

-- Component state tracking
function M.set_component_state(component, state, details)
    component_states[component] = state
    M.debug("STATE", component .. " -> " .. state, details)
end

function M.get_component_state(component)
    return component_states[component]
end

-- Safe function wrapper
function M.safe_call(component, func_name, func, ...)
    M.enter_function(component, func_name, {...})
    
    local ok, result = pcall(func, ...)
    
    if ok then
        M.exit_function(component, func_name, result)
        return true, result
    else
        M.error(component, "CRASH in " .. func_name, result)
        M.exit_function(component, func_name, "ERROR")
        return false, result
    end
end

-- Validate input parameters
function M.validate_input(component, func_name, validations)
    for param_name, validation in pairs(validations) do
        local value = validation.value
        local type_check = validation.type
        local required = validation.required
        local custom_check = validation.check
        
        if required and (value == nil) then
            M.error(component, func_name .. ": missing required parameter " .. param_name)
            return false, "Missing required parameter: " .. param_name
        end
        
        if value ~= nil and type_check and type(value) ~= type_check then
            M.error(component, func_name .. ": wrong type for " .. param_name, {
                expected = type_check,
                actual = type(value)
            })
            return false, "Wrong type for parameter: " .. param_name
        end
        
        if custom_check and not custom_check(value) then
            M.error(component, func_name .. ": validation failed for " .. param_name, value)
            return false, "Validation failed for parameter: " .. param_name
        end
    end
    
    return true
end

-- System health check
function M.health_check()
    local health = {
        timestamp = os.time(),
        components = {},
        call_stack_depth = #function_call_stack,
        vim_version = vim.version and vim.version() or "unknown",
        neovim_features = {}
    }
    
    -- Check each component state
    for component, state in pairs(component_states) do
        health.components[component] = {
            state = state,
            last_error = nil -- Could be enhanced to track last errors
        }
    end
    
    -- Check Neovim features
    health.neovim_features.has_loop = vim.loop ~= nil
    health.neovim_features.has_fs = vim.fs ~= nil
    health.neovim_features.has_ui_select = vim.ui and vim.ui.select ~= nil
    
    M.info("HEALTH", "System health check completed", health)
    return health
end

-- Configuration
function M.set_log_level(level)
    current_log_level = level
    M.info("CONFIG", "Log level set to " .. level)
end

function M.enable_debug()
    DEBUG_ENABLED = true
    M.info("CONFIG", "Debug logging enabled")
end

function M.disable_debug()
    DEBUG_ENABLED = false
end

function M.set_log_file(file_path)
    LOG_FILE = file_path
    M.info("CONFIG", "Log file set to " .. (file_path or "none"))
end

-- Easy production debugging activation
function M.enable_production_debugging(log_file)
    DEBUG_ENABLED = true
    current_log_level = M.LOG_LEVELS.ERROR -- Only show errors and warnings in production
    if log_file then
        LOG_FILE = log_file
    end
    vim.notify("Pebble Bases: Debug mode enabled (errors only)", vim.log.levels.INFO)
end

-- Crash recovery helpers
function M.reset_state()
    function_call_stack = {}
    component_states = {
        cache = "reset",
        parser = "reset",
        filters = "reset", 
        formulas = "reset",
        views = "reset"
    }
    M.info("RECOVERY", "System state reset")
end

-- Current state dump for debugging
function M.dump_state()
    local state = {
        call_stack = function_call_stack,
        components = component_states,
        log_level = current_log_level,
        debug_enabled = DEBUG_ENABLED
    }
    M.info("DUMP", "Current system state", state)
    return state
end

return M
-- Enhanced configuration and validation for pebble.nvim completion
local M = {}

-- Default configuration templates
local DEFAULT_CONFIGS = {
    minimal = {
        completion = {
            enabled = true,
            nvim_cmp = { enabled = true },
            blink_cmp = { enabled = true },
        }
    },
    
    safe = {
        completion = {
            enabled = true,
            debug = false,
            prevent_conflicts = true,
            nvim_cmp = {
                enabled = true,
                priority = 100,
                max_item_count = 25,
                filetype_setup = true,
                auto_add_to_sources = true,
            },
            blink_cmp = {
                enabled = true,
                priority = 100,
                max_item_count = 25,
            },
        }
    },
    
    performance = {
        completion = {
            enabled = true,
            cache_ttl = 60000, -- 1 minute
            cache_max_size = 1000,
            debug = false,
            nvim_cmp = {
                enabled = true,
                priority = 150,
                max_item_count = 15, -- Fewer items for better performance
                filetype_setup = true,
                auto_add_to_sources = false, -- Manual setup for better control
            },
            blink_cmp = { enabled = false }, -- Disable to avoid conflicts
        }
    },
    
    debug = {
        completion = {
            enabled = true,
            debug = true,
            prevent_conflicts = false,
            nvim_cmp = {
                enabled = true,
                priority = 100,
                max_item_count = 50,
                debug = true,
                filetype_setup = true,
                auto_add_to_sources = true,
            },
            blink_cmp = {
                enabled = true,
                priority = 100,
                max_item_count = 50,
                debug = true,
            },
        }
    }
}

-- Configuration validation schema
local CONFIG_SCHEMA = {
    completion = {
        type = "table",
        fields = {
            enabled = { type = "boolean", default = true },
            debug = { type = "boolean", default = false },
            prevent_conflicts = { type = "boolean", default = true },
            cache_ttl = { type = "number", default = 30000, min = 1000 },
            cache_max_size = { type = "number", default = 2000, min = 100 },
            nvim_cmp = {
                type = "table",
                fields = {
                    enabled = { type = "boolean", default = true },
                    priority = { type = "number", default = 100, min = 1, max = 1000 },
                    max_item_count = { type = "number", default = 50, min = 1, max = 200 },
                    trigger_characters = { type = "table", default = { "[", "(" } },
                    keyword_length = { type = "number", default = 0, min = 0, max = 10 },
                    filetype_setup = { type = "boolean", default = true },
                    auto_add_to_sources = { type = "boolean", default = true },
                    debug = { type = "boolean", default = false },
                }
            },
            blink_cmp = {
                type = "table", 
                fields = {
                    enabled = { type = "boolean", default = true },
                    priority = { type = "number", default = 100, min = 1, max = 1000 },
                    max_item_count = { type = "number", default = 50, min = 1, max = 200 },
                    trigger_characters = { type = "table", default = { "[", "(" } },
                    debug = { type = "boolean", default = false },
                }
            }
        }
    }
}

-- Validate configuration against schema
function M.validate_config(config, schema, path)
    path = path or ""
    local errors = {}
    local warnings = {}
    
    if not config or type(config) ~= "table" then
        table.insert(errors, path .. ": expected table, got " .. type(config))
        return errors, warnings
    end
    
    -- Check each field in schema
    for field, field_schema in pairs(schema) do
        local field_path = path == "" and field or (path .. "." .. field)
        local field_value = config[field]
        
        if field_schema.type == "table" and field_schema.fields then
            -- Nested table validation
            if field_value == nil then
                config[field] = {}
                field_value = config[field]
            elseif type(field_value) ~= "table" then
                table.insert(errors, field_path .. ": expected table, got " .. type(field_value))
                config[field] = {}
                field_value = config[field]
            end
            
            local sub_errors, sub_warnings = M.validate_config(field_value, field_schema.fields, field_path)
            vim.list_extend(errors, sub_errors)
            vim.list_extend(warnings, sub_warnings)
            
        else
            -- Simple field validation
            if field_value == nil then
                if field_schema.default ~= nil then
                    config[field] = field_schema.default
                end
            else
                -- Type validation
                if field_schema.type and type(field_value) ~= field_schema.type then
                    table.insert(errors, field_path .. ": expected " .. field_schema.type .. ", got " .. type(field_value))
                    if field_schema.default ~= nil then
                        config[field] = field_schema.default
                        table.insert(warnings, field_path .. ": reset to default value")
                    end
                end
                
                -- Range validation for numbers
                if field_schema.type == "number" and type(field_value) == "number" then
                    if field_schema.min and field_value < field_schema.min then
                        table.insert(warnings, field_path .. ": value " .. field_value .. " below minimum " .. field_schema.min)
                        config[field] = field_schema.min
                    elseif field_schema.max and field_value > field_schema.max then
                        table.insert(warnings, field_path .. ": value " .. field_value .. " above maximum " .. field_schema.max)
                        config[field] = field_schema.max
                    end
                end
            end
        end
    end
    
    return errors, warnings
end

-- Get a validated configuration
function M.get_validated_config(user_config, preset)
    preset = preset or "safe"
    local base_config = vim.deepcopy(DEFAULT_CONFIGS[preset] or DEFAULT_CONFIGS.safe)
    
    -- Merge user config
    if user_config then
        base_config = vim.tbl_deep_extend("force", base_config, user_config)
    end
    
    -- Validate and normalize
    local errors, warnings = M.validate_config(base_config, CONFIG_SCHEMA)
    
    return base_config, errors, warnings
end

-- Interactive configuration wizard
function M.setup_wizard()
    local responses = {}
    
    -- Helper function for prompts
    local function prompt(question, default, type_check)
        local input = vim.fn.input(question .. (default and (" [" .. tostring(default) .. "]") or "") .. ": ")
        
        if input == "" and default ~= nil then
            return default
        end
        
        if type_check == "boolean" then
            local lower_input = input:lower()
            if lower_input == "true" or lower_input == "yes" or lower_input == "y" or lower_input == "1" then
                return true
            elseif lower_input == "false" or lower_input == "no" or lower_input == "n" or lower_input == "0" then
                return false
            else
                return default
            end
        elseif type_check == "number" then
            local num = tonumber(input)
            return num or default
        else
            return input
        end
    end
    
    print("=== Pebble Completion Setup Wizard ===")
    print("This will help you configure pebble.nvim completion.")
    print("Press Enter to accept defaults.")
    print("")
    
    -- Basic settings
    responses.enabled = prompt("Enable completion?", true, "boolean")
    if not responses.enabled then
        return { completion = { enabled = false } }
    end
    
    responses.debug = prompt("Enable debug mode?", false, "boolean")
    responses.prevent_conflicts = prompt("Prevent registration conflicts?", true, "boolean")
    
    -- Performance settings
    local performance_level = prompt("Performance level (1=high performance, 2=balanced, 3=feature rich)", "2", "number")
    
    if performance_level == 1 then
        responses.cache_ttl = 60000
        responses.max_item_count = 15
        responses.auto_add_to_sources = false
    elseif performance_level == 3 then
        responses.cache_ttl = 15000
        responses.max_item_count = 100
        responses.auto_add_to_sources = true
    else
        responses.cache_ttl = 30000
        responses.max_item_count = 50
        responses.auto_add_to_sources = true
    end
    
    -- Engine selection
    local has_nvim_cmp = pcall(require, "cmp")
    local has_blink_cmp = pcall(require, "blink.cmp")
    
    print("")
    print("Available completion engines:")
    if has_nvim_cmp then print("  ✓ nvim-cmp") else print("  ✗ nvim-cmp") end
    if has_blink_cmp then print("  ✓ blink.cmp") else print("  ✗ blink.cmp") end
    print("")
    
    local use_nvim_cmp = has_nvim_cmp and prompt("Use nvim-cmp?", true, "boolean")
    local use_blink_cmp = has_blink_cmp and not use_nvim_cmp and prompt("Use blink.cmp?", true, "boolean")
    
    if not use_nvim_cmp and not use_blink_cmp then
        print("Warning: No completion engines selected. Completion will be disabled.")
    end
    
    -- Build configuration
    local config = {
        completion = {
            enabled = responses.enabled,
            debug = responses.debug,
            prevent_conflicts = responses.prevent_conflicts,
            cache_ttl = responses.cache_ttl,
            nvim_cmp = {
                enabled = use_nvim_cmp,
                max_item_count = responses.max_item_count,
                auto_add_to_sources = responses.auto_add_to_sources,
                debug = responses.debug,
            },
            blink_cmp = {
                enabled = use_blink_cmp,
                max_item_count = responses.max_item_count,
                debug = responses.debug,
            },
        }
    }
    
    -- Validate the generated config
    local validated_config, errors, warnings = M.get_validated_config(config)
    
    if #errors > 0 then
        print("Configuration errors detected:")
        for _, error in ipairs(errors) do
            print("  ✗ " .. error)
        end
        return nil
    end
    
    if #warnings > 0 then
        print("Configuration warnings:")
        for _, warning in ipairs(warnings) do
            print("  ⚠ " .. warning)
        end
    end
    
    print("")
    print("Generated configuration:")
    print(vim.inspect(validated_config))
    print("")
    
    local save_config = prompt("Save this configuration to your init.lua?", false, "boolean")
    
    if save_config then
        local config_str = "require('pebble').setup(" .. vim.inspect(validated_config, { indent = "  " }) .. ")"
        print("")
        print("Add this to your Neovim configuration:")
        print("")
        print(config_str)
        print("")
        
        -- Try to write to clipboard if available
        local has_clipboard = vim.fn.has('clipboard') == 1
        if has_clipboard then
            vim.fn.setreg('+', config_str)
            print("Configuration copied to clipboard!")
        end
    end
    
    return validated_config
end

-- Get preset configurations
function M.get_preset(name)
    return DEFAULT_CONFIGS[name] and vim.deepcopy(DEFAULT_CONFIGS[name]) or nil
end

-- List available presets
function M.list_presets()
    local presets = {}
    for name, _ in pairs(DEFAULT_CONFIGS) do
        table.insert(presets, name)
    end
    return presets
end

-- Apply configuration with validation
function M.apply_config(config, preset)
    local validated_config, errors, warnings = M.get_validated_config(config, preset)
    
    if #errors > 0 then
        local error_msg = "Pebble configuration errors:\n" .. table.concat(errors, "\n")
        vim.notify(error_msg, vim.log.levels.ERROR)
        return false, errors, warnings
    end
    
    if #warnings > 0 then
        local warning_msg = "Pebble configuration warnings:\n" .. table.concat(warnings, "\n")
        vim.notify(warning_msg, vim.log.levels.WARN)
    end
    
    return validated_config, errors, warnings
end

return M
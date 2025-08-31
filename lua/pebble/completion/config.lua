local M = {}

-- Default tag extraction patterns optimized for performance
M.default_patterns = {
    -- Inline tags: #tag, #category/subcategory
    inline = {
        simple = "#([a-zA-Z0-9_-]+)",
        nested = "#([a-zA-Z0-9_/-]+)",
        complex = "#([a-zA-Z0-9_][a-zA-Z0-9_/-]*[a-zA-Z0-9_]|[a-zA-Z0-9_])",
    },
    
    -- YAML frontmatter patterns
    frontmatter = {
        -- Array format: tags: [tag1, tag2, tag3]
        array = "tags:\\s*\\[([^\\]]+)\\]",
        
        -- List format: tags: \n  - tag1 \n  - tag2
        list_item = "^\\s*-\\s+([a-zA-Z0-9_/-]+)",
        
        -- Single value: tags: single-tag
        single = "tags:\\s*([a-zA-Z0-9_/-]+)\\s*$",
        
        -- Categories format: categories: [cat1, cat2]
        categories = "categories:\\s*\\[([^\\]]+)\\]",
    }
}

-- Preset configurations for different use cases
M.presets = {
    -- Maximum performance - basic patterns only
    performance = {
        inline_tag_pattern = M.default_patterns.inline.simple,
        frontmatter_tag_pattern = M.default_patterns.frontmatter.array,
        file_patterns = { "*.md" },
        max_files_scan = 500,
        cache_ttl = 120000,  -- 2 minutes
        async_extraction = true,
        max_completion_items = 30,
    },
    
    -- Balanced - good performance with more features
    balanced = {
        inline_tag_pattern = M.default_patterns.inline.nested,
        frontmatter_tag_pattern = M.default_patterns.frontmatter.array .. "|" .. M.default_patterns.frontmatter.list_item,
        file_patterns = { "*.md", "*.markdown" },
        max_files_scan = 1000,
        cache_ttl = 60000,  -- 1 minute
        async_extraction = true,
        fuzzy_matching = true,
        nested_tag_support = true,
        max_completion_items = 50,
    },
    
    -- Comprehensive - all features enabled
    comprehensive = {
        inline_tag_pattern = M.default_patterns.inline.complex,
        frontmatter_tag_pattern = 
            M.default_patterns.frontmatter.array .. "|" ..
            M.default_patterns.frontmatter.list_item .. "|" ..
            M.default_patterns.frontmatter.single .. "|" ..
            M.default_patterns.frontmatter.categories,
        file_patterns = { "*.md", "*.markdown", "*.txt", "*.org" },
        max_files_scan = 2000,
        cache_ttl = 30000,  -- 30 seconds for fresh results
        async_extraction = true,
        fuzzy_matching = true,
        nested_tag_support = true,
        max_completion_items = 100,
        frequency_weight = 0.6,
        recency_weight = 0.4,
    },
    
    -- Obsidian-style configuration
    obsidian = {
        inline_tag_pattern = "#([a-zA-Z0-9_][a-zA-Z0-9_/-]*)",
        frontmatter_tag_pattern = "tags:\\s*\\[([^\\]]+)\\]",
        file_patterns = { "*.md" },
        max_files_scan = 1000,
        cache_ttl = 60000,
        async_extraction = true,
        fuzzy_matching = true,
        nested_tag_support = true,
        max_completion_items = 50,
        trigger_pattern = "#",
    },
    
    -- Logseq-style configuration
    logseq = {
        inline_tag_pattern = "#([a-zA-Z0-9_-]+)",
        frontmatter_tag_pattern = "tags::\\s*([^\\n]+)",
        file_patterns = { "*.md" },
        max_files_scan = 800,
        cache_ttl = 45000,
        async_extraction = true,
        fuzzy_matching = true,
        nested_tag_support = false,  -- Logseq uses different nesting
        max_completion_items = 40,
    },
}

-- Build configuration from preset and overrides
function M.build_config(preset_name, overrides)
    overrides = overrides or {}
    
    local base_config
    if preset_name and M.presets[preset_name] then
        base_config = vim.deepcopy(M.presets[preset_name])
    else
        base_config = vim.deepcopy(M.presets.balanced)
    end
    
    return vim.tbl_deep_extend("force", base_config, overrides)
end

-- Validate configuration
function M.validate_config(config)
    local errors = {}
    
    -- Check required fields
    if not config.inline_tag_pattern or config.inline_tag_pattern == "" then
        table.insert(errors, "inline_tag_pattern is required")
    end
    
    if not config.file_patterns or #config.file_patterns == 0 then
        table.insert(errors, "file_patterns must contain at least one pattern")
    end
    
    -- Validate numeric fields
    local numeric_fields = {
        "max_files_scan", "cache_ttl", "max_completion_items",
        "frequency_weight", "recency_weight"
    }
    
    for _, field in ipairs(numeric_fields) do
        if config[field] and type(config[field]) ~= "number" then
            table.insert(errors, field .. " must be a number")
        end
    end
    
    -- Validate weights sum to reasonable range
    if config.frequency_weight and config.recency_weight then
        local sum = config.frequency_weight + config.recency_weight
        if sum > 1.5 or sum < 0.5 then
            table.insert(errors, "frequency_weight + recency_weight should be close to 1.0")
        end
    end
    
    -- Validate ripgrep patterns
    if config.inline_tag_pattern then
        local ok = pcall(vim.fn.matchadd, "Test", config.inline_tag_pattern)
        if not ok then
            table.insert(errors, "inline_tag_pattern is not a valid regex pattern")
        end
    end
    
    return #errors == 0, errors
end

-- Get suggested configuration based on environment
function M.detect_environment()
    local suggestions = {}
    
    -- Check if in Obsidian vault (has .obsidian directory)
    if vim.fn.isdirectory(".obsidian") == 1 then
        suggestions.preset = "obsidian"
        suggestions.reason = "Detected Obsidian vault"
    
    -- Check if using Logseq (has logseq directory or config)
    elseif vim.fn.isdirectory("logseq") == 1 or vim.fn.filereadable("logseq/config.edn") == 1 then
        suggestions.preset = "logseq"
        suggestions.reason = "Detected Logseq directory"
    
    -- Check repository size to suggest performance preset
    else
        local root_dir = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
        if vim.v.shell_error == 0 and root_dir ~= "" then
            local md_count = vim.fn.system("find '" .. root_dir .. "' -name '*.md' | wc -l"):gsub("\n", "")
            local count = tonumber(md_count) or 0
            
            if count > 2000 then
                suggestions.preset = "performance"
                suggestions.reason = "Large repository detected (" .. count .. " markdown files)"
            elseif count > 500 then
                suggestions.preset = "balanced"
                suggestions.reason = "Medium repository detected (" .. count .. " markdown files)"
            else
                suggestions.preset = "comprehensive"
                suggestions.reason = "Small repository detected (" .. count .. " markdown files)"
            end
        else
            suggestions.preset = "balanced"
            suggestions.reason = "Default balanced configuration"
        end
    end
    
    return suggestions
end

-- Interactive configuration wizard
function M.setup_wizard()
    local suggestions = M.detect_environment()
    
    print("=== Pebble Tag Completion Setup Wizard ===")
    print("Environment detected: " .. suggestions.reason)
    print("Suggested preset: " .. suggestions.preset)
    print("")
    
    -- Ask user for confirmation
    local choice = vim.fn.input("Use suggested preset '" .. suggestions.preset .. "'? (y/n/custom): ")
    
    if choice:lower() == "n" then
        print("\nAvailable presets:")
        for name, _ in pairs(M.presets) do
            print("  - " .. name)
        end
        local preset_choice = vim.fn.input("Enter preset name: ")
        if M.presets[preset_choice] then
            suggestions.preset = preset_choice
        else
            print("Invalid preset, using balanced")
            suggestions.preset = "balanced"
        end
    elseif choice:lower() == "custom" then
        print("\nCustom configuration not implemented in wizard yet.")
        print("Please configure manually in your init.lua")
        return nil
    end
    
    local config = M.build_config(suggestions.preset)
    local is_valid, errors = M.validate_config(config)
    
    if not is_valid then
        print("Configuration validation failed:")
        for _, error in ipairs(errors) do
            print("  - " .. error)
        end
        return nil
    end
    
    print("\nConfiguration created successfully!")
    print("Preset: " .. suggestions.preset)
    print("Add this to your init.lua:")
    print("")
    print("require('pebble').setup({")
    print("  completion = {")
    print("    tags = require('pebble.completion.config').build_config('" .. suggestions.preset .. "')")
    print("  }")
    print("})")
    print("")
    
    return config
end

-- Performance optimization suggestions
function M.get_performance_suggestions(current_config)
    local suggestions = {}
    
    -- Check cache TTL
    if current_config.cache_ttl and current_config.cache_ttl < 30000 then
        table.insert(suggestions, {
            type = "performance",
            message = "Consider increasing cache_ttl to reduce file scanning frequency"
        })
    end
    
    -- Check max files scan
    if current_config.max_files_scan and current_config.max_files_scan > 1500 then
        table.insert(suggestions, {
            type = "performance",
            message = "Consider reducing max_files_scan for better performance in large repositories"
        })
    end
    
    -- Check async extraction
    if not current_config.async_extraction then
        table.insert(suggestions, {
            type = "performance",
            message = "Enable async_extraction for better UI responsiveness"
        })
    end
    
    -- Check completion items
    if current_config.max_completion_items and current_config.max_completion_items > 80 then
        table.insert(suggestions, {
            type = "ui",
            message = "Consider reducing max_completion_items for cleaner completion menu"
        })
    end
    
    return suggestions
end

return M
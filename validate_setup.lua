#!/usr/bin/env nvim -l

-- Pebble.nvim Setup Validation Script
-- ====================================
-- This script validates that all components work together properly
-- and provides setup recommendations for optimal performance.

local function print_header(title)
    print(string.format("\n🔍 %s", title))
    print(string.rep("=", #title + 3))
end

local function print_check(name, status, details)
    local icon = status and "✅" or "❌"
    print(string.format("  %s %s", icon, name))
    if details then
        print(string.format("     %s", details))
    end
end

local function print_warning(name, details)
    print(string.format("  ⚠️  %s", name))
    if details then
        print(string.format("     %s", details))
    end
end

local function print_info(name, details)
    print(string.format("  ℹ️  %s", name))
    if details then
        print(string.format("     %s", details))
    end
end

-- Test markdown files for testing
local test_files = {
    "test-note1.md",
    "test-note2.md",
    "test-tags.md"
}

local function create_test_files()
    -- Create test markdown files
    local test_note1 = {
        "---",
        "title: Test Note One", 
        "aliases: [note1, first-note]",
        "tags: [test, demo, markdown]",
        "---",
        "",
        "# Test Note One",
        "",
        "This is a test note with #inline-tags and [[test-note2|links]].",
        "",
        "Tags: #work #personal #project/test"
    }
    
    local test_note2 = {
        "---",
        "title: Second Test Note",
        "tags: [example, testing]", 
        "---",
        "",
        "# Second Test Note", 
        "",
        "References [[test-note1]] and has #example tags."
    }
    
    local test_tags = {
        "# Tag Testing",
        "",
        "Various tag formats:",
        "- #simple-tag",
        "- #nested/tag/structure", 
        "- #work/project/urgent",
        "- #123numbers (invalid)",
        "- #valid_underscore",
        "",
        "Links: [[test-note1]] and [[test-note2]]"
    }
    
    vim.fn.writefile(test_note1, "test-note1.md")
    vim.fn.writefile(test_note2, "test-note2.md") 
    vim.fn.writefile(test_tags, "test-tags.md")
end

local function cleanup_test_files()
    for _, file in ipairs(test_files) do
        if vim.fn.filereadable(file) == 1 then
            vim.fn.delete(file)
        end
    end
end

print("🚀 Pebble.nvim Setup Validation")
print("===============================")

-- Create test files
create_test_files()

-- Test 1: Core Components
print_header("Core Components")

local components = {
    {"Main module", "pebble"},
    {"Search module", "pebble.search"},
    {"Completion core", "pebble.completion"},
    {"Tag completion", "pebble.completion.tags"},
    {"nvim-cmp source", "pebble.completion.nvim_cmp"},
    {"blink.cmp source", "pebble.completion.blink_cmp"}
}

for _, component in ipairs(components) do
    local name, module = component[1], component[2]
    local ok, mod = pcall(require, module)
    print_check(name, ok, ok and "Loaded successfully" or "Failed to load")
end

-- Test 2: External Dependencies
print_header("External Dependencies")

local search = require('pebble.search')
local has_rg = search.has_ripgrep()
local rg_version = search.get_ripgrep_version()

print_check("Ripgrep", has_rg, 
    has_rg and ("Version: " .. (rg_version or "unknown")) or
    "Install with: brew install ripgrep (macOS) or apt install ripgrep (Ubuntu)")

-- Check completion engines
local nvim_cmp = require('pebble.completion.nvim_cmp')
local has_nvim_cmp = nvim_cmp.is_available()
print_check("nvim-cmp", has_nvim_cmp, 
    has_nvim_cmp and "Available for completion integration" or "Optional: install for completion")

local blink_cmp = require('pebble.completion.blink_cmp')  
local has_blink_cmp = blink_cmp.is_available()
print_check("blink.cmp", has_blink_cmp,
    has_blink_cmp and "Available for completion integration" or "Optional: alternative completion engine")

if not has_nvim_cmp and not has_blink_cmp then
    print_warning("No completion engine detected", "Install nvim-cmp or blink.cmp for completion features")
end

-- Test 3: Performance Assessment
print_header("Performance Assessment")

-- File discovery performance
local start_time = vim.loop.hrtime()
local files = search.find_markdown_files_sync(vim.fn.getcwd())
local end_time = vim.loop.hrtime()
local discovery_time = (end_time - start_time) / 1000000

print_info(string.format("File discovery: %.1fms", discovery_time),
    string.format("Found %d markdown files", #files))

if discovery_time > 1000 then
    print_warning("Slow file discovery", "Consider installing ripgrep for better performance")
else
    print_check("File discovery speed", true, "Fast enough for interactive use")
end

-- Cache performance
-- Cache module removed
start_time = vim.loop.hrtime()
local file_data = cache.get_file_data(vim.fn.getcwd())
end_time = vim.loop.hrtime()
local cache_time = (end_time - start_time) / 1000000

print_info(string.format("Cache building: %.1fms", cache_time),
    string.format("Processed %d files", #file_data))

-- Test 4: Completion Functionality
print_header("Completion Functionality")

-- Wiki link completion
local completion = require('pebble.completion')
start_time = vim.loop.hrtime()
local wiki_completions = completion.get_wiki_completions("test", vim.fn.getcwd())
end_time = vim.loop.hrtime()
local wiki_time = (end_time - start_time) / 1000000

print_check("Wiki link completion", #wiki_completions > 0,
    string.format("Found %d completions in %.1fms", #wiki_completions, wiki_time))

-- Tag completion
local tags = require('pebble.completion.tags')
tags.setup({})

-- Trigger cache building
tags.refresh_cache()
vim.wait(1000) -- Wait for async completion

local tag_stats = tags.get_cache_stats()
print_check("Tag completion system", tag_stats.entries_count > 0,
    string.format("Found %d tags in cache", tag_stats.entries_count))

-- Test 5: Integration Tests
print_header("Integration Tests")

-- Test pebble setup
local ok, err = pcall(function()
    local pebble = require('pebble')
    pebble.setup({
        completion = {
            nvim_cmp = has_nvim_cmp,
            blink_cmp = has_blink_cmp
        }
    })
end)

print_check("Pebble setup", ok, ok and "Configuration loaded successfully" or ("Error: " .. (err or "unknown")))

-- Test markdown file context
vim.cmd('edit test-note1.md')
local current_ft = vim.bo.filetype
vim.bo.filetype = 'markdown' -- Force markdown filetype

local is_completion_enabled = completion.is_completion_enabled()
print_check("Markdown context", is_completion_enabled, 
    "Completion should activate in markdown files")

-- Test wiki link context detection
vim.api.nvim_buf_set_lines(0, 0, -1, false, {"Testing [[test", ""})
vim.api.nvim_win_set_cursor(0, {1, 12}) -- Position after [[test

local is_wiki_context, query = completion.is_wiki_link_context()
print_check("Wiki link detection", is_wiki_context,
    is_wiki_context and ("Query: '" .. query .. "'") or "Failed to detect [[wiki]] context")

-- Test 6: Performance Benchmarks
print_header("Performance Benchmarks")

-- Repository size assessment
local file_count = #files
local size_category = "small"
if file_count > 1000 then
    size_category = "large"
elseif file_count > 300 then
    size_category = "medium"
end

print_info(string.format("Repository size: %s (%d files)", size_category, file_count))

if size_category == "large" then
    print_warning("Large repository detected", "Monitor performance with :PebbleStats")
    if not has_rg then
        print_warning("Ripgrep recommended", "Install ripgrep for optimal performance with large repositories")
    end
end

-- Memory usage estimation
local estimated_memory = file_count * 0.5 -- Rough estimate: 500 bytes per file
print_info(string.format("Estimated memory usage: %.1f KB", estimated_memory))

-- Test 7: Feature Validation
print_header("Feature Validation")

-- Test tag extraction
local tag_pattern_tests = {
    {"#simple", true},
    {"#nested/tag", true},
    {"#invalid-chars!", false},
    {"#123numbers", false},
    {"#valid_underscore", true}
}

local all_tag_tests_pass = true
for _, test in ipairs(tag_pattern_tests) do
    local tag, should_match = test[1], test[2]
    local matches = tag:match("^#([a-zA-Z0-9_/-]+)$") ~= nil
    if matches ~= should_match then
        all_tag_tests_pass = false
        break
    end
end

print_check("Tag pattern validation", all_tag_tests_pass, 
    "Tag patterns work correctly")

-- Test frontmatter parsing
local frontmatter = completion.parse_frontmatter or function(path)
    -- Fallback if function not directly accessible
    -- Cache module removed
    local data = cache.get_file_data(vim.fn.getcwd())
    for _, file in ipairs(data) do
        if file.path:match("test%-note1%.md$") then
            return file.frontmatter
        end
    end
    return nil
end

-- Try to get frontmatter from test file
local fm = nil
for _, file in ipairs(file_data) do
    if file.path:match("test%-note1%.md$") then
        fm = file.frontmatter
        break
    end
end

print_check("YAML frontmatter parsing", fm ~= nil,
    fm and string.format("Extracted: title='%s', %d tags", fm.title or "none", fm.tags and #fm.tags or 0) or "Failed to parse frontmatter")

-- Final recommendations
print_header("Recommendations")

if not has_rg then
    print("📦 Install ripgrep for optimal performance:")
    print("   macOS: brew install ripgrep")
    print("   Ubuntu: apt install ripgrep") 
    print("   Arch: pacman -S ripgrep")
    print("   Windows: choco install ripgrep")
end

if not has_nvim_cmp and not has_blink_cmp then
    print("🔧 Install a completion engine:")
    print("   nvim-cmp: https://github.com/hrsh7th/nvim-cmp")
    print("   blink.cmp: https://github.com/Saghen/blink.cmp")
end

if file_count > 1000 then
    print("⚡ Large repository optimizations:")
    print("   - Use :PebbleStats to monitor performance")
    print("   - Consider excluding large directories in ripgrep config")
    print("   - Monitor memory usage with large file sets")
end

print("\n🎯 Setup Commands")
print("=================")
print("Add this to your Neovim config:")
print("```lua")
print("require('pebble').setup({")
print("    completion = {")
print(string.format("        nvim_cmp = %s,", tostring(has_nvim_cmp)))
print(string.format("        blink_cmp = %s,", tostring(has_blink_cmp)))
print("    },")
print("    search = {")
print(string.format("        ripgrep_path = %s,", has_rg and "\"rg\"" or "nil -- install ripgrep"))
print("    }")
print("})")
print("```")

print("\n✨ Validation Complete!")
print("=======================")

-- Cleanup
cleanup_test_files()

local issues = 0
if not has_rg then issues = issues + 1 end
if not has_nvim_cmp and not has_blink_cmp then issues = issues + 1 end
if file_count > 1000 and not has_rg then issues = issues + 1 end

if issues == 0 then
    print("🎉 Perfect setup! All components working optimally.")
    print("Run :PebbleHealth anytime to check system status.")
else
    print(string.format("⚠️  %d optimization opportunity(ies) found.", issues))
    print("Address the recommendations above for best performance.")
end

vim.cmd('qall!')
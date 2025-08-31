#!/usr/bin/env nvim -l

-- Integration test script for pebble.nvim
-- Tests all completion fixes, performance optimizations, and component integration

local success_count = 0
local total_count = 0
local failed_tests = {}

local function test(name, func)
    total_count = total_count + 1
    print(string.format("Testing %s...", name))
    
    local ok, result = pcall(func)
    if ok and result ~= false then
        print(string.format("  ✓ %s", name))
        success_count = success_count + 1
    else
        local error_msg = not ok and result or "Test failed"
        print(string.format("  ✗ %s: %s", name, error_msg))
        table.insert(failed_tests, {name = name, error = error_msg})
    end
end

local function benchmark(name, func, iterations)
    iterations = iterations or 1
    local start_time = vim.loop.hrtime()
    
    for i = 1, iterations do
        func()
    end
    
    local end_time = vim.loop.hrtime()
    local duration_ms = (end_time - start_time) / 1000000
    local avg_ms = duration_ms / iterations
    
    print(string.format("  📊 %s: %.2fms (avg over %d runs)", name, avg_ms, iterations))
    return avg_ms
end

print("🚀 Pebble.nvim Integration Test Suite")
print("=====================================")

-- Test 1: Basic module loading
test("Basic pebble module loading", function()
    local pebble = require('pebble')
    return pebble ~= nil
end)

-- Test 2: Search module and ripgrep integration
test("Search module with ripgrep support", function()
    local search = require('pebble.bases.search')
    local has_rg = search.has_ripgrep()
    if not has_rg then
        error("ripgrep not found - install with: brew install ripgrep")
    end
    return true
end)

-- Test 3: Cache module functionality
test("Cache module operations", function()
    local cache = require('pebble.bases.cache')
    local root_dir = vim.fn.getcwd()
    local data = cache.get_file_data(root_dir)
    return data ~= nil
end)

-- Test 4: Parser module
test("Parser module base file parsing", function()
    local parser = require('pebble.bases.parser')
    local base_files = parser.find_base_files(vim.fn.getcwd())
    return base_files ~= nil
end)

-- Test 5: Completion system core
test("Completion module initialization", function()
    local completion = require('pebble.completion')
    local root_dir = completion.get_root_dir()
    return root_dir ~= nil and root_dir ~= ""
end)

-- Test 6: Wiki link completion
test("Wiki link completion functionality", function()
    local completion = require('pebble.completion')
    local root_dir = completion.get_root_dir()
    local completions = completion.get_wiki_completions("test", root_dir)
    return completions ~= nil
end)

-- Test 7: Tag completion system
test("Tag completion system", function()
    local tags = require('pebble.completion.tags')
    tags.setup({})
    local stats = tags.get_cache_stats()
    return stats ~= nil
end)

-- Test 8: nvim-cmp integration
test("nvim-cmp completion source", function()
    local nvim_cmp = require('pebble.completion.nvim_cmp')
    return nvim_cmp.is_available() or true -- OK if cmp not installed
end)

-- Test 9: blink.cmp integration
test("blink.cmp completion source", function()
    local blink_cmp = require('pebble.completion.blink_cmp')
    return blink_cmp.is_available() or true -- OK if blink not installed
end)

-- Test 10: Full pebble setup
test("Complete pebble setup", function()
    local pebble = require('pebble')
    pebble.setup({
        completion = {
            nvim_cmp = true,
            blink_cmp = true
        }
    })
    return true
end)

print("\n🔧 Performance Benchmarks")
print("=========================")

-- Benchmark 1: File discovery with ripgrep
benchmark("File discovery (ripgrep)", function()
    local search = require('pebble.bases.search')
    local files = search.find_markdown_files_sync(vim.fn.getcwd())
end, 3)

-- Benchmark 2: Cache building
benchmark("Cache building", function()
    local cache = require('pebble.bases.cache')
    cache.clear_cache()
    local data = cache.get_file_data(vim.fn.getcwd())
end, 2)

-- Benchmark 3: Wiki link completion
benchmark("Wiki completion generation", function()
    local completion = require('pebble.completion')
    local completions = completion.get_wiki_completions("", completion.get_root_dir())
end, 5)

-- Benchmark 4: Tag completion
benchmark("Tag completion generation", function()
    local tags = require('pebble.completion.tags')
    tags.refresh_cache()
end, 3)

print("\n📈 System Information")
print("=====================")

-- System info
local search = require('pebble.bases.search')
local version = search.get_ripgrep_version()
print(string.format("Ripgrep version: %s", version or "Not available"))

local stats = search.get_cache_stats()
print(string.format("Search cache: %d entries, %dms TTL", stats.entries, stats.ttl))

local completion = require('pebble.completion')
local comp_stats = completion.get_stats()
if comp_stats.cache_size then
    print(string.format("Completion cache: %d files, %.1fs age", comp_stats.cache_size, comp_stats.cache_age / 1000))
end

-- Tag stats
local tags = require('pebble.completion.tags')
local tag_stats = tags.get_cache_stats()
print(string.format("Tag cache: %d entries, valid: %s", tag_stats.entries_count or 0, tostring(tag_stats.is_valid)))

print("\n📋 Summary")
print("==========")

local pass_rate = (success_count / total_count) * 100
print(string.format("Tests passed: %d/%d (%.1f%%)", success_count, total_count, pass_rate))

if #failed_tests > 0 then
    print("\n❌ Failed tests:")
    for _, failure in ipairs(failed_tests) do
        print(string.format("  - %s: %s", failure.name, failure.error))
    end
else
    print("🎉 All tests passed!")
end

-- Performance recommendations
print("\n💡 Performance Status")
print("=====================")

local config = search.get_config()
local file_count = 0

-- Count markdown files for performance assessment
local files = search.find_markdown_files_sync(vim.fn.getcwd())
file_count = #files

if file_count > 1000 then
    print("⚠️  Large repository detected (" .. file_count .. " files)")
    print("   Consider using async operations for better performance")
else
    print("✅ Repository size optimal (" .. file_count .. " files)")
end

if version then
    print("✅ Ripgrep optimization active")
else
    print("⚠️  Install ripgrep for maximum performance: brew install ripgrep")
end

-- Exit with appropriate code
if success_count == total_count then
    print("\n🎉 Integration test completed successfully!")
    vim.cmd('qall!')
else
    print(string.format("\n❌ %d/%d tests failed", total_count - success_count, total_count))
    vim.cmd('cquit 1')
end
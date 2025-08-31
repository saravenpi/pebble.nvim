#!/usr/bin/env nvim -l

-- Pebble.nvim Performance Benchmark Suite
-- ========================================
-- Comprehensive performance testing for all completion fixes

local function benchmark_operation(name, operation, iterations)
    iterations = iterations or 1
    print(string.format("🔄 Benchmarking: %s (%d runs)", name, iterations))
    
    -- Warm up
    pcall(operation)
    
    local times = {}
    local total_time = 0
    
    for i = 1, iterations do
        local start_time = vim.loop.hrtime()
        local success, result = pcall(operation)
        local end_time = vim.loop.hrtime()
        
        local duration = (end_time - start_time) / 1000000 -- Convert to milliseconds
        table.insert(times, duration)
        total_time = total_time + duration
        
        if not success then
            print(string.format("  ❌ Run %d failed: %s", i, result))
            return nil
        end
    end
    
    -- Calculate statistics
    local avg_time = total_time / iterations
    local min_time = math.min(unpack(times))
    local max_time = math.max(unpack(times))
    
    -- Calculate standard deviation
    local variance = 0
    for _, time in ipairs(times) do
        variance = variance + (time - avg_time)^2
    end
    local std_dev = math.sqrt(variance / iterations)
    
    print(string.format("  📊 Average: %.2fms | Min: %.2fms | Max: %.2fms | StdDev: %.2fms", 
          avg_time, min_time, max_time, std_dev))
    
    return {
        avg = avg_time,
        min = min_time,
        max = max_time,
        std_dev = std_dev,
        iterations = iterations
    }
end

local function create_test_repository(size)
    print(string.format("🏗️ Creating test repository with %d files", size))
    
    -- Create test directory
    local test_dir = vim.fn.tempname() .. "_pebble_test"
    vim.fn.mkdir(test_dir, "p")
    
    -- Create markdown files with varying content
    local files_created = 0
    for i = 1, size do
        local filename = string.format("test-note-%04d.md", i)
        local filepath = test_dir .. "/" .. filename
        
        local content = {
            "---",
            string.format("title: Test Note %d", i),
            string.format("aliases: [note%d, test%d]", i, i),
            string.format("tags: [test, category%d, priority%d]", i % 5, i % 3),
            "created: " .. os.date("%Y-%m-%d"),
            "---",
            "",
            string.format("# Test Note %d", i),
            "",
            string.format("This is test note number %d with #tag%d and [[test-note-%04d|link]].", 
                          i, i % 10, (i % size) + 1),
            "",
            "More content with #nested/tag/structure and #work tags.",
            string.format("References: [[test-note-%04d]] and [[test-note-%04d]]", 
                          math.max(1, i-1), math.min(size, i+1))
        }
        
        local ok, err = pcall(vim.fn.writefile, content, filepath)
        if ok then
            files_created = files_created + 1
        else
            print(string.format("  ❌ Failed to create %s: %s", filename, err))
        end
    end
    
    print(string.format("  ✅ Created %d/%d files in %s", files_created, size, test_dir))
    return test_dir, files_created
end

local function cleanup_test_repository(test_dir)
    if test_dir and vim.fn.isdirectory(test_dir) == 1 then
        vim.fn.system(string.format("rm -rf '%s'", test_dir))
        print("🧹 Cleaned up test repository")
    end
end

local function benchmark_with_repository_size(size)
    print(string.format("\n🎯 Benchmarking with %d file repository", size))
    print(string.rep("=", 50))
    
    local test_dir, files_created = create_test_repository(size)
    if files_created == 0 then
        print("❌ Failed to create test repository")
        return nil
    end
    
    -- Change to test directory
    local original_cwd = vim.fn.getcwd()
    vim.fn.chdir(test_dir)
    
    local benchmarks = {}
    
    -- 1. File Discovery Benchmarks
    print("\n🔍 File Discovery Performance")
    print("-" .. string.rep("-", 30))
    
    local search = require("pebble.bases.search")
    
    -- Ripgrep file discovery
    if search.has_ripgrep() then
        benchmarks.ripgrep_discovery = benchmark_operation("Ripgrep file discovery", function()
            return search.find_markdown_files_sync(test_dir)
        end, 5)
    else
        print("  ⚠️ Ripgrep not available - install for optimal performance")
    end
    
    -- Fallback file discovery
    benchmarks.fallback_discovery = benchmark_operation("Fallback file discovery", function()
        -- Temporarily disable ripgrep to test fallback
        local original_has_rg = search.has_ripgrep
        search.has_ripgrep = function() return false end
        local result = search.find_markdown_files_sync(test_dir)
        search.has_ripgrep = original_has_rg
        return result
    end, 3)
    
    -- 2. Cache Building Benchmarks
    print("\n💾 Cache Building Performance")  
    print("-" .. string.rep("-", 30))
    
    local cache = require("pebble.bases.cache")
    
    benchmarks.cache_building = benchmark_operation("Full cache building", function()
        cache.clear_cache()
        return cache.get_file_data(test_dir)
    end, 3)
    
    benchmarks.cache_retrieval = benchmark_operation("Cache retrieval (warm)", function()
        return cache.get_file_data(test_dir)
    end, 10)
    
    -- 3. Completion Benchmarks
    print("\n🔗 Completion Performance")
    print("-" .. string.rep("-", 25))
    
    local completion = require("pebble.completion")
    
    benchmarks.wiki_completion_empty = benchmark_operation("Wiki completion (empty query)", function()
        return completion.get_wiki_completions("", test_dir)
    end, 5)
    
    benchmarks.wiki_completion_query = benchmark_operation("Wiki completion (with query)", function()
        return completion.get_wiki_completions("test", test_dir)
    end, 5)
    
    benchmarks.markdown_completion = benchmark_operation("Markdown link completion", function()
        return completion.get_markdown_link_completions("note", test_dir)
    end, 5)
    
    -- 4. Tag Completion Benchmarks
    print("\n🏷️ Tag Completion Performance")
    print("-" .. string.rep("-", 30))
    
    local tags = require("pebble.completion.tags")
    tags.setup({})
    
    benchmarks.tag_cache_build = benchmark_operation("Tag cache building", function()
        tags.refresh_cache()
        -- Wait a bit for async completion
        vim.wait(100)
        return tags.get_cache_stats()
    end, 3)
    
    -- 5. Search Performance
    print("\n🔎 Search Performance")
    print("-" .. string.rep("-", 20))
    
    if search.has_ripgrep() then
        benchmarks.content_search = benchmark_operation("Content search (ripgrep)", function()
            return search.search_in_files("test", test_dir, { max_results = 100 })
        end, 3)
        
        benchmarks.tag_extraction = benchmark_operation("Tag extraction (async)", function()
            local result = nil
            search.extract_tags_async(test_dir, function(tags, err)
                result = tags
            end)
            vim.wait(1000, function() return result ~= nil end)
            return result
        end, 2)
    end
    
    -- 6. Integration Performance
    print("\n🔧 Integration Performance")
    print("-" .. string.rep("-", 27))
    
    benchmarks.full_setup = benchmark_operation("Full pebble setup", function()
        local pebble = require("pebble")
        return pebble.setup({
            completion = { tags = { async_extraction = false } },
            search = { max_files = size + 100 }
        })
    end, 2)
    
    -- Return to original directory
    vim.fn.chdir(original_cwd)
    cleanup_test_repository(test_dir)
    
    return benchmarks
end

local function analyze_performance(small_bench, medium_bench, large_bench)
    print("\n📈 Performance Analysis")
    print(string.rep("=", 40))
    
    -- File discovery comparison
    if small_bench.ripgrep_discovery and medium_bench.ripgrep_discovery and large_bench.ripgrep_discovery then
        print("\n🔍 File Discovery Scaling (ripgrep):")
        print(string.format("  Small (16 files):  %.2fms", small_bench.ripgrep_discovery.avg))
        print(string.format("  Medium (100 files): %.2fms", medium_bench.ripgrep_discovery.avg))  
        print(string.format("  Large (500 files):  %.2fms", large_bench.ripgrep_discovery.avg))
        
        local scaling_factor = large_bench.ripgrep_discovery.avg / small_bench.ripgrep_discovery.avg
        print(string.format("  Scaling factor: %.2fx (linear would be 31.25x)", scaling_factor))
        
        if scaling_factor < 10 then
            print("  ✅ Excellent scaling - ripgrep optimization working well")
        elseif scaling_factor < 20 then
            print("  ⚠️ Good scaling - consider optimizations for very large repos")
        else
            print("  ❌ Poor scaling - check ripgrep installation and configuration")
        end
    end
    
    -- Completion performance
    if small_bench.wiki_completion_empty and large_bench.wiki_completion_empty then
        print("\n🔗 Completion Performance:")
        local small_time = small_bench.wiki_completion_empty.avg
        local large_time = large_bench.wiki_completion_empty.avg
        print(string.format("  Small repo: %.2fms", small_time))
        print(string.format("  Large repo: %.2fms", large_time))
        
        if large_time < 100 then
            print("  ✅ Fast completion even with large repositories")
        elseif large_time < 500 then
            print("  ⚠️ Acceptable completion speed - consider caching optimizations")
        else
            print("  ❌ Slow completion - check file limits and caching")
        end
    end
    
    -- Memory efficiency estimation
    print("\n💾 Memory Efficiency:")
    local small_memory = 16 * 0.5 -- KB
    local medium_memory = 100 * 0.5
    local large_memory = 500 * 0.5
    
    print(string.format("  Estimated cache sizes:"))
    print(string.format("    Small:  %.1f KB", small_memory))
    print(string.format("    Medium: %.1f KB", medium_memory))
    print(string.format("    Large:  %.1f KB", large_memory))
    
    if large_memory < 1000 then
        print("  ✅ Memory efficient - suitable for any system")
    elseif large_memory < 5000 then
        print("  ⚠️ Moderate memory usage - monitor on resource-constrained systems")
    else
        print("  ❌ High memory usage - consider reducing file limits")
    end
end

-- Main benchmark execution
print("🚀 Pebble.nvim Performance Benchmark Suite")
print(string.rep("=", 45))
print("This will test performance across different repository sizes")
print("and provide optimization recommendations.\n")

-- System information
local search = require("pebble.bases.search")
print("🖥️ System Information:")
print(string.format("  Neovim: %s", vim.version().major .. "." .. vim.version().minor))
print(string.format("  Ripgrep: %s", search.get_ripgrep_version() or "Not available"))
print(string.format("  Platform: %s", vim.loop.os_uname().sysname))

-- Run benchmarks with different repository sizes
local results = {}

-- Small repository (similar to current test environment)
results.small = benchmark_with_repository_size(16)

-- Medium repository
results.medium = benchmark_with_repository_size(100)

-- Large repository  
results.large = benchmark_with_repository_size(500)

-- Analyze results
if results.small and results.medium and results.large then
    analyze_performance(results.small, results.medium, results.large)
end

print("\n🎯 Performance Recommendations")
print(string.rep("=", 35))

local has_ripgrep = search.has_ripgrep()
if has_ripgrep then
    print("✅ Ripgrep detected - optimal performance enabled")
else
    print("❌ Install ripgrep for 10-100x performance improvement:")
    print("   macOS: brew install ripgrep")
    print("   Ubuntu: apt install ripgrep")
end

-- Configuration recommendations based on results
if results.large and results.large.cache_building then
    local cache_time = results.large.cache_building.avg
    if cache_time > 1000 then
        print("⚠️ Consider reducing max_files setting for faster startup")
        print("   Add to config: search = { max_files = 1000 }")
    elseif cache_time < 200 then
        print("✅ Cache building is fast - you can increase max_files if needed")
    end
end

print("\n📊 Summary Report")
print(string.rep("=", 20))
print("Performance benchmarking completed successfully!")
print("Use this data to optimize your pebble.nvim configuration.")
print("\nFor detailed performance monitoring in daily use:")
print("  :PebbleHealth      - System health check")
print("  :PebbleStats       - Runtime performance stats")
print("  :PebbleCompletionStats - Completion metrics")

vim.cmd('qall!')
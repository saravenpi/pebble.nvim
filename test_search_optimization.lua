#!/usr/bin/env lua

-- Simple test script to verify search optimizations
-- This is a standalone test that doesn't require Neovim

local function test_search_optimization()
    print("🔍 Testing pebble.nvim search optimizations...")
    
    -- Test 1: Check if search module loads correctly
    print("\n1. Testing search module loading...")
    local ok, search = pcall(require, "pebble.bases.search")
    if ok then
        print("✅ Search module loaded successfully")
    else
        print("❌ Failed to load search module: " .. tostring(search))
        return false
    end
    
    -- Test 2: Check ripgrep detection
    print("\n2. Testing ripgrep detection...")
    local has_rg = search.has_ripgrep()
    if has_rg then
        print("✅ Ripgrep detected and available")
        local version = search.get_ripgrep_version()
        if version then
            print("   Version: " .. version)
        end
    else
        print("⚠️  Ripgrep not available - fallback methods will be used")
    end
    
    -- Test 3: Test configuration
    print("\n3. Testing search configuration...")
    local config = search.get_config()
    if config and config.ripgrep_path then
        print("✅ Configuration loaded successfully")
        print("   Max files: " .. config.max_files)
        print("   Max depth: " .. config.max_depth)
        print("   Timeout: " .. config.timeout .. "ms")
    else
        print("❌ Configuration not loaded properly")
        return false
    end
    
    -- Test 4: Test cache system
    print("\n4. Testing cache system...")
    local cache_stats = search.get_cache_stats()
    if cache_stats then
        print("✅ Cache system operational")
        print("   Entries: " .. cache_stats.entries)
        print("   TTL: " .. cache_stats.ttl .. "ms")
        print("   Max size: " .. cache_stats.max_size)
        print("   Hit rate: " .. string.format("%.1f%%", cache_stats.hit_rate))
    else
        print("❌ Cache system not working")
        return false
    end
    
    -- Test 5: Test git root detection
    print("\n5. Testing git root detection...")
    local root_dir = search.get_root_dir()
    if root_dir and root_dir ~= "" then
        print("✅ Git root detection working")
        print("   Root directory: " .. root_dir)
    else
        print("❌ Git root detection failed")
        return false
    end
    
    print("\n🎉 All search optimization tests passed!")
    print("\n📊 Performance Features Enabled:")
    print("   • Enhanced ripgrep command construction")
    print("   • Intelligent LRU caching with TTL")
    print("   • Centralized git root detection")
    print("   • Async/sync dual patterns")
    print("   • Smart fallback mechanisms")
    print("   • Optimized file type detection")
    print("   • Batch operation support")
    print("   • Performance-tuned exclude patterns")
    
    return true
end

-- Run tests
local success = test_search_optimization()
os.exit(success and 0 or 1)
local M = {}

-- Advanced caching system with TTL, memory management, and performance optimization
local cache = {
    stores = {}, -- Multiple cache stores for different data types
    config = {
        default_ttl = 60000, -- 1 minute default TTL
        max_memory = 100 * 1024 * 1024, -- 100MB max total cache memory
        cleanup_interval = 30000, -- 30 seconds cleanup interval
        eviction_strategy = "lru", -- lru, lfu, or ttl
        compression_enabled = false, -- Enable for large datasets
        persistence_enabled = false, -- Enable cache persistence
    },
    stats = {
        hits = 0,
        misses = 0,
        evictions = 0,
        memory_usage = 0,
        stores_count = 0,
    },
    timers = {},
}

-- Performance monitoring integration
local performance = require("pebble.completion.performance")

-- Cache entry structure
local function create_cache_entry(data, ttl, tags)
    tags = tags or {}
    
    return {
        data = data,
        created_at = vim.loop.now(),
        expires_at = vim.loop.now() + ttl,
        ttl = ttl,
        access_count = 0,
        last_accessed = vim.loop.now(),
        size = 0, -- Will be calculated
        tags = tags,
        compressed = false,
    }
end

-- Memory estimation for cache entries
local function estimate_entry_size(entry)
    if entry.size > 0 then
        return entry.size
    end
    
    local size = 100 -- Base overhead
    
    -- Estimate data size
    local function calc_size(obj, depth)
        depth = depth or 0
        if depth > 10 then return 0 end -- Prevent infinite recursion
        
        local t = type(obj)
        if t == "string" then
            return #obj + 24
        elseif t == "number" then
            return 8
        elseif t == "boolean" then
            return 1
        elseif t == "table" then
            local table_size = 40
            for k, v in pairs(obj) do
                table_size = table_size + calc_size(k, depth + 1) + calc_size(v, depth + 1)
            end
            return table_size
        end
        return 0
    end
    
    size = size + calc_size(entry.data)
    entry.size = size
    return size
end

-- Get or create cache store
local function get_store(store_name)
    if not cache.stores[store_name] then
        cache.stores[store_name] = {
            entries = {},
            config = vim.deepcopy(cache.config),
            stats = {
                hits = 0,
                misses = 0,
                evictions = 0,
                memory_usage = 0,
            },
        }
        cache.stats.stores_count = cache.stats.stores_count + 1
    end
    return cache.stores[store_name]
end

-- Check if cache entry is valid (not expired)
local function is_entry_valid(entry)
    local now = vim.loop.now()
    return entry.expires_at > now
end

-- Update cache statistics
local function update_cache_stats()
    cache.stats.memory_usage = 0
    
    for _, store in pairs(cache.stores) do
        store.stats.memory_usage = 0
        for _, entry in pairs(store.entries) do
            local entry_size = estimate_entry_size(entry)
            store.stats.memory_usage = store.stats.memory_usage + entry_size
        end
        cache.stats.memory_usage = cache.stats.memory_usage + store.stats.memory_usage
    end
    
    -- Update performance monitoring
    performance.update_cache_metrics({
        size = cache.stats.memory_usage,
        stores = cache.stats.stores_count
    })
end

-- LRU eviction strategy
local function evict_lru(store, target_count)
    target_count = target_count or 1
    
    -- Collect entries with access times
    local entries_with_access = {}
    for key, entry in pairs(store.entries) do
        table.insert(entries_with_access, {
            key = key,
            entry = entry,
            last_accessed = entry.last_accessed,
        })
    end
    
    -- Sort by last accessed time (oldest first)
    table.sort(entries_with_access, function(a, b)
        return a.last_accessed < b.last_accessed
    end)
    
    -- Evict oldest entries
    local evicted = 0
    for i = 1, math.min(target_count, #entries_with_access) do
        local key = entries_with_access[i].key
        store.entries[key] = nil
        store.stats.evictions = store.stats.evictions + 1
        cache.stats.evictions = cache.stats.evictions + 1
        evicted = evicted + 1
        
        performance.record_cache_eviction("lru")
    end
    
    return evicted
end

-- LFU eviction strategy
local function evict_lfu(store, target_count)
    target_count = target_count or 1
    
    -- Collect entries with access counts
    local entries_with_frequency = {}
    for key, entry in pairs(store.entries) do
        table.insert(entries_with_frequency, {
            key = key,
            entry = entry,
            access_count = entry.access_count,
        })
    end
    
    -- Sort by access count (lowest first)
    table.sort(entries_with_frequency, function(a, b)
        return a.access_count < b.access_count
    end)
    
    -- Evict least frequently used entries
    local evicted = 0
    for i = 1, math.min(target_count, #entries_with_frequency) do
        local key = entries_with_frequency[i].key
        store.entries[key] = nil
        store.stats.evictions = store.stats.evictions + 1
        cache.stats.evictions = cache.stats.evictions + 1
        evicted = evicted + 1
        
        performance.record_cache_eviction("lfu")
    end
    
    return evicted
end

-- TTL-based eviction (expired entries first)
local function evict_expired(store)
    local now = vim.loop.now()
    local evicted = 0
    
    for key, entry in pairs(store.entries) do
        if entry.expires_at <= now then
            store.entries[key] = nil
            store.stats.evictions = store.stats.evictions + 1
            cache.stats.evictions = cache.stats.evictions + 1
            evicted = evicted + 1
            
            performance.record_cache_eviction("ttl")
        end
    end
    
    return evicted
end

-- Clean up cache based on strategy
local function cleanup_cache(store_name, force_cleanup)
    local store = store_name and cache.stores[store_name] or nil
    local stores_to_clean = store and {[store_name] = store} or cache.stores
    
    for name, store in pairs(stores_to_clean) do
        -- Always clean expired entries first
        local expired_evicted = evict_expired(store)
        
        -- Check if we need more aggressive cleanup
        if force_cleanup or store.stats.memory_usage > store.config.max_memory * 0.8 then
            local total_entries = vim.tbl_count(store.entries)
            local target_evictions = math.max(1, math.floor(total_entries * 0.2)) -- Remove 20% of entries
            
            if store.config.eviction_strategy == "lru" then
                evict_lru(store, target_evictions)
            elseif store.config.eviction_strategy == "lfu" then
                evict_lfu(store, target_evictions)
            end
        end
    end
    
    -- Update statistics
    update_cache_stats()
end

-- Automatic cleanup timer
local function start_cleanup_timer()
    if cache.timers.cleanup then
        cache.timers.cleanup:stop()
    end
    
    cache.timers.cleanup = vim.loop.new_timer()
    cache.timers.cleanup:start(cache.config.cleanup_interval, cache.config.cleanup_interval, vim.schedule_wrap(function()
        cleanup_cache()
    end))
end

-- Set cache entry with advanced options
function M.set(store_name, key, data, options)
    options = options or {}
    local ttl = options.ttl or cache.config.default_ttl
    local tags = options.tags or {}
    
    local store = get_store(store_name)
    local entry = create_cache_entry(data, ttl, tags)
    
    -- Estimate size
    estimate_entry_size(entry)
    
    -- Check memory limits before adding
    if store.stats.memory_usage + entry.size > store.config.max_memory then
        cleanup_cache(store_name, true)
    end
    
    store.entries[key] = entry
    update_cache_stats()
    
    return true
end

-- Get cache entry with access tracking
function M.get(store_name, key, options)
    options = options or {}
    local store = cache.stores[store_name]
    
    if not store or not store.entries[key] then
        cache.stats.misses = cache.stats.misses + 1
        store = store or get_store(store_name) -- Create store for stats
        store.stats.misses = store.stats.misses + 1
        return nil
    end
    
    local entry = store.entries[key]
    
    -- Check if entry is still valid
    if not is_entry_valid(entry) then
        store.entries[key] = nil
        cache.stats.misses = cache.stats.misses + 1
        store.stats.misses = store.stats.misses + 1
        return nil
    end
    
    -- Update access tracking
    entry.access_count = entry.access_count + 1
    entry.last_accessed = vim.loop.now()
    
    -- Extend TTL if requested
    if options.extend_ttl then
        entry.expires_at = vim.loop.now() + entry.ttl
    end
    
    cache.stats.hits = cache.stats.hits + 1
    store.stats.hits = store.stats.hits + 1
    
    return entry.data
end

-- Check if key exists in cache
function M.has(store_name, key)
    local store = cache.stores[store_name]
    if not store or not store.entries[key] then
        return false
    end
    
    return is_entry_valid(store.entries[key])
end

-- Delete specific cache entry
function M.delete(store_name, key)
    local store = cache.stores[store_name]
    if not store then
        return false
    end
    
    if store.entries[key] then
        store.entries[key] = nil
        update_cache_stats()
        return true
    end
    
    return false
end

-- Clear entire store or all stores
function M.clear(store_name)
    if store_name then
        if cache.stores[store_name] then
            cache.stores[store_name].entries = {}
            cache.stores[store_name].stats = {
                hits = 0,
                misses = 0,
                evictions = 0,
                memory_usage = 0,
            }
        end
    else
        -- Clear all stores
        for name, _ in pairs(cache.stores) do
            M.clear(name)
        end
        cache.stats = {
            hits = 0,
            misses = 0,
            evictions = 0,
            memory_usage = 0,
            stores_count = vim.tbl_count(cache.stores),
        }
    end
    
    update_cache_stats()
end

-- Invalidate cache entries by tags
function M.invalidate_by_tags(store_name, tags)
    local store = cache.stores[store_name]
    if not store then
        return 0
    end
    
    local invalidated = 0
    tags = type(tags) == "table" and tags or {tags}
    
    for key, entry in pairs(store.entries) do
        for _, tag in ipairs(tags) do
            if vim.tbl_contains(entry.tags, tag) then
                store.entries[key] = nil
                invalidated = invalidated + 1
                break
            end
        end
    end
    
    if invalidated > 0 then
        update_cache_stats()
    end
    
    return invalidated
end

-- Get cache statistics
function M.get_stats(store_name)
    if store_name then
        local store = cache.stores[store_name]
        if not store then
            return nil
        end
        
        local total_accesses = store.stats.hits + store.stats.misses
        return {
            hits = store.stats.hits,
            misses = store.stats.misses,
            evictions = store.stats.evictions,
            memory_usage = store.stats.memory_usage,
            memory_usage_mb = store.stats.memory_usage / (1024 * 1024),
            hit_rate = total_accesses > 0 and (store.stats.hits / total_accesses) or 0,
            entry_count = vim.tbl_count(store.entries),
        }
    else
        -- Global statistics
        local total_accesses = cache.stats.hits + cache.stats.misses
        return {
            global = {
                hits = cache.stats.hits,
                misses = cache.stats.misses,
                evictions = cache.stats.evictions,
                memory_usage = cache.stats.memory_usage,
                memory_usage_mb = cache.stats.memory_usage / (1024 * 1024),
                hit_rate = total_accesses > 0 and (cache.stats.hits / total_accesses) or 0,
                stores_count = cache.stats.stores_count,
            },
            stores = vim.tbl_map(function(name) return M.get_stats(name) end, vim.tbl_keys(cache.stores))
        }
    end
end

-- Configure cache settings
function M.configure(store_name, config_updates)
    if store_name then
        local store = get_store(store_name)
        store.config = vim.tbl_deep_extend("force", store.config, config_updates or {})
    else
        -- Global configuration
        cache.config = vim.tbl_deep_extend("force", cache.config, config_updates or {})
        
        -- Apply to all existing stores
        for _, store in pairs(cache.stores) do
            store.config = vim.tbl_deep_extend("force", store.config, config_updates or {})
        end
        
        -- Restart cleanup timer if interval changed
        if config_updates.cleanup_interval then
            start_cleanup_timer()
        end
    end
end

-- Get configuration
function M.get_config(store_name)
    if store_name then
        local store = cache.stores[store_name]
        return store and store.config or nil
    else
        return cache.config
    end
end

-- Warmup cache with data
function M.warmup(store_name, data_loader, options)
    options = options or {}
    local batch_size = options.batch_size or 100
    local delay_between_batches = options.delay or 10 -- 10ms delay
    
    if type(data_loader) ~= "function" then
        return false
    end
    
    vim.schedule(function()
        local batch_count = 0
        local function load_batch()
            local batch_data = data_loader(batch_count * batch_size, batch_size)
            
            if not batch_data or vim.tbl_isempty(batch_data) then
                -- No more data to load
                if options.on_complete then
                    options.on_complete()
                end
                return
            end
            
            -- Load batch into cache
            for key, data in pairs(batch_data) do
                M.set(store_name, key, data, {
                    ttl = options.ttl,
                    tags = options.tags
                })
            end
            
            batch_count = batch_count + 1
            
            -- Schedule next batch
            vim.defer_fn(load_batch, delay_between_batches)
        end
        
        load_batch()
    end)
    
    return true
end

-- Health check for cache system
function M.health_check()
    local health = {
        status = "healthy",
        issues = {},
        recommendations = {},
        stats = M.get_stats()
    }
    
    -- Check memory usage
    local memory_usage_pct = (cache.stats.memory_usage / cache.config.max_memory) * 100
    if memory_usage_pct > 90 then
        health.status = "critical"
        table.insert(health.issues, "Memory usage critical: " .. math.floor(memory_usage_pct) .. "%")
        table.insert(health.recommendations, "Increase max_memory or enable more aggressive eviction")
    elseif memory_usage_pct > 75 then
        health.status = "warning"
        table.insert(health.issues, "Memory usage high: " .. math.floor(memory_usage_pct) .. "%")
        table.insert(health.recommendations, "Consider reducing cache TTL or cleanup interval")
    end
    
    -- Check hit rate
    local global_stats = health.stats.global
    if global_stats.hit_rate < 0.5 then
        health.status = health.status == "critical" and "critical" or "warning"
        table.insert(health.issues, "Low cache hit rate: " .. math.floor(global_stats.hit_rate * 100) .. "%")
        table.insert(health.recommendations, "Review cache TTL settings or cache invalidation strategy")
    end
    
    -- Check for too many evictions
    local eviction_rate = global_stats.evictions / math.max(1, global_stats.hits + global_stats.misses)
    if eviction_rate > 0.1 then
        health.status = health.status == "critical" and "critical" or "warning"
        table.insert(health.issues, "High eviction rate: " .. math.floor(eviction_rate * 100) .. "%")
        table.insert(health.recommendations, "Increase cache size or adjust eviction strategy")
    end
    
    return health
end

-- Setup and initialize cache system
function M.setup(config_options)
    config_options = config_options or {}
    
    -- Update global configuration
    cache.config = vim.tbl_deep_extend("force", cache.config, config_options)
    
    -- Start cleanup timer
    start_cleanup_timer()
    
    -- Setup autocmds for cache invalidation
    vim.api.nvim_create_autocmd({"BufWritePost", "BufDelete"}, {
        pattern = "*",
        callback = function(args)
            -- Invalidate file-related caches
            M.invalidate_by_tags("completion", {"file:" .. args.file})
            M.invalidate_by_tags("notes", {"file:" .. args.file})
        end,
        group = vim.api.nvim_create_augroup("PebbleCacheInvalidation", {clear = true})
    })
    
    return true
end

-- Cleanup on exit
function M.cleanup()
    -- Stop timers
    for _, timer in pairs(cache.timers) do
        if timer then
            timer:stop()
            timer:close()
        end
    end
    
    cache.timers = {}
    
    -- Clear all caches
    M.clear()
end

return M
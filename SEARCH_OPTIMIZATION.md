# Pebble.nvim Search Optimization

This document describes the ripgrep-based search optimizations implemented in pebble.nvim for improved performance when working with large collections of markdown files.

## Overview

The search functionality has been completely rewritten to use ripgrep for fast file discovery, content searching, and link/tag extraction. This provides significant performance improvements over the previous file system traversal methods.

## Key Optimizations

### 1. Ripgrep Integration (`lua/pebble/bases/search.lua`)

- **Async Operations**: All ripgrep operations use `vim.system()` (Neovim 0.10+) or `vim.fn.jobstart()` fallback for non-blocking execution
- **Smart Caching**: Results are cached for 10 seconds to avoid redundant operations
- **Fallback Support**: Gracefully falls back to `find` command when ripgrep is not available
- **Configuration**: Extensive configuration options for ripgrep parameters

**Key Features:**
- Fast markdown file discovery with `find_markdown_files_async()`
- Optimized base file discovery with `find_base_files_async()`
- Content searching with `search_in_files_async()`
- Tag extraction with `extract_tags_async()`
- Link extraction with `extract_links_async()`

### 2. Optimized Caching (`lua/pebble/bases/cache.lua`)

- **Async File Processing**: Files are processed in batches to avoid UI blocking
- **Large File Handling**: Files over 1MB are handled specially to prevent performance issues
- **Improved Frontmatter Parsing**: More efficient YAML frontmatter extraction
- **Smart Batching**: Processes files in configurable batch sizes

### 3. Enhanced File Discovery

- **Deeper Search**: Increased max depth from 3 to 5 levels
- **Better Exclusions**: More comprehensive exclusion patterns for common directories
- **Higher Limits**: Increased file limits with better performance characteristics

## Configuration Options

Configure search behavior in your `setup()` call:

```lua
require('pebble').setup({
    search = {
        ripgrep_path = "rg",           -- Path to ripgrep executable
        max_files = 2000,              -- Maximum files to process
        max_depth = 10,                -- Maximum directory depth
        timeout = 30000,               -- Timeout in milliseconds
        exclude_patterns = {           -- Additional patterns to exclude
            "*.tmp",
            "backup/*"
        }
    }
})
```

### Default Configuration

- **Max files**: 2000
- **Max depth**: 10 levels
- **Timeout**: 30 seconds
- **Cache TTL**: 10 seconds
- **Default exclusions**: `.git`, `node_modules`, `.obsidian`, `build`, `dist`, `target`, `.venv`, `.tox`, `*.lock`, `*.tmp`

## Performance Benefits

### Before Optimization
- Used `vim.fs.find()` with limited recursion
- Synchronous operations blocked UI
- Limited to 500 files to prevent freezing
- Basic exclusion patterns
- No caching of search results

### After Optimization
- Uses ripgrep for subsecond file discovery
- Async operations don't block UI
- Can handle 2000+ files efficiently
- Comprehensive exclusion patterns
- Smart caching reduces redundant operations
- Batch processing prevents UI freezing

## Backward Compatibility

The optimization maintains full backward compatibility:

- All existing functions continue to work
- Fallback to previous methods when ripgrep is unavailable
- Same API surface for calling code
- Configuration is optional (sensible defaults)

## Requirements

### Recommended
- **ripgrep**: Install via `brew install ripgrep`, `apt install ripgrep`, etc.
- **Neovim 0.10+**: For best async performance with `vim.system()`

### Fallback Support
- Works on Neovim 0.8+ with `vim.fn.jobstart()`
- Falls back to `find` command when ripgrep is not available
- Ultimate fallback to Lua-based directory traversal

## API Changes

### New Async Functions
```lua
-- Async versions with callbacks
search.find_markdown_files_async(root_dir, callback)
search.find_base_files_async(root_dir, callback)
search.search_in_files_async(pattern, root_dir, options, callback)
search.extract_tags_async(root_dir, callback)
search.extract_links_async(root_dir, callback)

-- Enhanced cache functions
cache.get_file_data_async(root_dir, force_refresh, callback)

-- Enhanced parser functions
parser.find_base_files_async(root_dir, callback)
```

### Configuration Functions
```lua
search.setup(config)           -- Configure search behavior
search.get_config()           -- Get current configuration
search.clear_cache()          -- Clear search caches
search.get_cache_stats()      -- Get cache statistics
search.has_ripgrep()          -- Check ripgrep availability
search.get_ripgrep_version()  -- Get ripgrep version
```

## Error Handling

The implementation includes comprehensive error handling:

- Graceful degradation when ripgrep is unavailable
- Timeout protection for long-running operations
- Safe file system operations with `pcall()` protection
- Informative error messages for debugging

## Performance Monitoring

Monitor search performance with:

```lua
-- Check cache statistics
:lua print(vim.inspect(require('pebble.bases.search').get_cache_stats()))

-- Check if ripgrep is available
:lua print(require('pebble.bases.search').has_ripgrep())

-- Clear caches if needed
:lua require('pebble.bases.search').clear_cache()
```

## Troubleshooting

### Ripgrep Not Found
If ripgrep is not available, the plugin will:
1. Show a warning in search operations
2. Fall back to `find` command
3. Use Lua-based traversal as ultimate fallback

### Performance Issues
If you experience performance issues:
1. Reduce `max_files` in configuration
2. Add more exclusion patterns for your specific setup
3. Reduce `max_depth` for shallower searches
4. Clear caches with `search.clear_cache()`

### Large Repositories
For very large repositories:
1. Use more aggressive exclusion patterns
2. Consider reducing `max_files` and `max_depth`
3. Ensure ripgrep is installed for best performance
4. Monitor memory usage with large file counts

## Implementation Details

The optimization uses a three-tier approach:

1. **Primary**: Ripgrep with async operations
2. **Secondary**: System `find` command fallback  
3. **Tertiary**: Lua-based directory traversal

This ensures reliability across different environments while maximizing performance where possible.
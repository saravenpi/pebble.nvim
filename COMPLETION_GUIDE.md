# Pebble Link Completion System

The Pebble plugin provides intelligent completion for both Wiki links (`[[link]]`) and Markdown links (`[text](link)`).

## Features

- **Wiki Link Completion**: Type `[[` to trigger completion for wiki-style links
- **Markdown Link Completion**: Type `](` to trigger completion for markdown link paths
- **Fuzzy Matching**: Smart fuzzy search across filenames, titles, and aliases
- **YAML Frontmatter Support**: Reads titles and aliases from YAML frontmatter
- **Fast File Discovery**: Uses ripgrep for optimal performance with fallbacks
- **Multiple Engine Support**: Works with both nvim-cmp and blink.cmp
- **Intelligent Caching**: Efficient caching system with automatic invalidation

## Setup

### Basic Setup

```lua
require("pebble").setup({
  completion = {
    enabled = true,
    nvim_cmp = { enabled = true },
    blink_cmp = { enabled = true },
  }
})
```

### Advanced Configuration

```lua
require("pebble").setup({
  completion = {
    enabled = true,
    debug = false, -- Enable debug logging
    cache_ttl = 30000, -- Cache time-to-live in milliseconds
    cache_max_size = 2000, -- Maximum number of files to cache
    
    -- nvim-cmp specific settings
    nvim_cmp = {
      enabled = true,
      priority = 100,
      max_item_count = 50,
      trigger_characters = { "[", "(" },
      keyword_length = 0,
    },
    
    -- blink.cmp specific settings
    blink_cmp = {
      enabled = true,
      priority = 100,
      max_item_count = 50,
      trigger_characters = { "[", "(" },
    }
  }
})
```

## Usage

### Wiki Links

1. Type `[[` in a markdown file
2. Start typing the name of a file, title, or alias
3. Select from the completion menu
4. The completion will insert just the link name (without file extension)

Example:
```markdown
Check out [[my-important-note]] for more details.
```

### Markdown Links

1. Type `[link text](` in a markdown file  
2. Start typing the path or name of a file
3. Select from the completion menu
4. The completion will insert the relative file path

Example:
```markdown
See [my note](./path/to/my-important-note.md) for details.
```

### YAML Frontmatter Support

Files with YAML frontmatter are fully supported:

```markdown
---
title: "My Important Note"
aliases: ["important", "key-note", "main-doc"]
tags: ["documentation", "important"]
---

# My Important Note

Content here...
```

When completing, you can match against:
- Filename: `my-important-note`
- Title: `My Important Note`
- Aliases: `important`, `key-note`, `main-doc`

## Commands

### Testing Commands

- `:PebbleTestCompletion` - Test completion in current cursor context
- `:PebbleCompletionStatus` - Show detailed status and statistics
- `:PebbleRefreshCache` - Manually refresh the file cache

### Example Testing Workflow

1. Open a markdown file
2. Type `[[test` (but don't press Enter)
3. Run `:PebbleTestCompletion`
4. You should see available completions for "test"

## Completion Engine Integration

### nvim-cmp Integration

The plugin automatically registers with nvim-cmp when available. Make sure you have nvim-cmp configured:

```lua
local cmp = require('cmp')

cmp.setup({
  sources = cmp.config.sources({
    -- Your other sources
    { name = 'pebble' }, -- This will be added automatically
  })
})
```

### blink.cmp Integration

The plugin automatically registers with blink.cmp when available:

```lua
require('blink.cmp').setup({
  sources = {
    -- Your other sources
    -- 'pebble' source will be added automatically
  }
})
```

## Performance Optimization

### Ripgrep Integration

For optimal performance, install ripgrep:

```bash
# macOS
brew install ripgrep

# Ubuntu/Debian
sudo apt install ripgrep

# Windows
winget install BurntSushi.ripgrep.MSVC
```

### Fallback Methods

If ripgrep is not available, the plugin will fall back to:
1. `vim.fs.find()` (Neovim 0.8+)
2. `vim.fn.glob()` (all versions)

### Caching

The plugin implements intelligent caching:
- Files are cached for 30 seconds by default
- Cache is automatically invalidated when files change
- Maximum 2000 files cached by default
- Batch processing prevents UI blocking

## Troubleshooting

### No Completions Appearing

1. Check that completion is enabled: `:PebbleCompletionStatus`
2. Verify you're in the right context: `:PebbleTestCompletion`
3. Check for markdown files in your directory
4. Ensure your completion engine (nvim-cmp or blink.cmp) is working

### Slow Performance

1. Install ripgrep for faster file discovery
2. Reduce `cache_max_size` if you have many files
3. Check `:PebbleCompletionStatus` for cache statistics

### Completion Not Triggering

1. Ensure you're in a markdown file (`:set filetype=markdown`)
2. Check trigger characters are correct (`[[` or `](`)
3. Verify completion engine integration: `:PebbleCompletionStatus`

### Debug Mode

Enable debug logging to troubleshoot issues:

```lua
require("pebble").setup({
  completion = {
    debug = true
  }
})
```

## Technical Details

### File Discovery

The system discovers markdown files using multiple strategies:
1. **Ripgrep** (fastest): `rg --files --type md`
2. **vim.fs.find** (fast): Native Neovim API
3. **vim.fn.glob** (compatible): Works on all versions

### Context Detection

The plugin intelligently detects completion contexts:
- **Wiki links**: Searches backwards for `[[` pattern
- **Markdown links**: Searches backwards for `](` pattern
- **Boundary detection**: Stops at closing brackets or newlines

### Fuzzy Matching

The fuzzy matching algorithm provides intelligent scoring:
- Exact matches: Highest priority (1000 points)
- Prefix matches: High priority (900+ points)
- Word boundary matches: Medium priority (700+ points)
- Consecutive character matches: Variable scoring
- Shorter targets preferred for conciseness

### Cache Management

The caching system is designed for performance:
- **TTL-based expiration**: 30-second default lifetime
- **Size limits**: Prevents memory bloat
- **Automatic invalidation**: File change detection
- **Error handling**: Failed operations are cached to prevent retries
# Pebble Tag Completion

Ultra-fast tag completion for pebble.nvim using ripgrep-powered tag extraction. Provides intelligent # completion with frequency-based scoring, fuzzy matching, and nested tag support.

## Features

- **Ultra-fast performance**: Ripgrep-powered tag extraction with intelligent caching
- **Multiple tag sources**: Supports both inline tags (`#tag`) and YAML frontmatter tags
- **Nested tag hierarchy**: Support for tags like `#category/subcategory/item`
- **Fuzzy matching**: Smart completion with fuzzy search capabilities
- **Frequency scoring**: Prioritizes commonly used tags in completion results
- **Dual completion engine support**: Works with both nvim-cmp and blink.cmp
- **Auto-caching**: Intelligent cache refresh on file changes
- **Configurable patterns**: Customize tag extraction patterns for your workflow

## Quick Setup

### Basic Setup (Recommended)

```lua
require('pebble').setup({
  completion = {
    tags = require('pebble.completion.config').build_config('balanced')
  }
})
```

### Auto-detected Setup

```lua
-- Let pebble detect your environment and suggest optimal settings
require('pebble').setup({
  completion = {
    tags = require('pebble.completion.config').build_config()  -- Auto-detects best preset
  }
})
```

### Custom Configuration

```lua
require('pebble').setup({
  completion = {
    tags = {
      -- Trigger pattern
      trigger_pattern = "#",
      
      -- Tag extraction patterns
      inline_tag_pattern = "#([a-zA-Z0-9_/-]+)",
      frontmatter_tag_pattern = "tags:\\s*\\[([^\\]]+)\\]|tags:\\s*-\\s*([^\\n]+)",
      
      -- File patterns to search
      file_patterns = { "*.md", "*.markdown", "*.txt" },
      
      -- Performance settings
      max_files_scan = 1000,
      cache_ttl = 60000,  -- 1 minute
      async_extraction = true,
      
      -- UI options
      max_completion_items = 50,
      fuzzy_matching = true,
      nested_tag_support = true,
      
      -- Scoring weights
      frequency_weight = 0.7,
      recency_weight = 0.3,
    }
  }
})
```

## Configuration Presets

The plugin includes several optimized presets for different use cases:

### `performance` - Maximum Speed
```lua
tags = require('pebble.completion.config').build_config('performance')
```
- Basic inline tag extraction only
- Limited to 500 files
- 2-minute cache TTL
- Best for large repositories (2000+ files)

### `balanced` - Recommended Default
```lua
tags = require('pebble.completion.config').build_config('balanced')
```
- Inline + frontmatter array tags
- Up to 1000 files
- 1-minute cache TTL
- Fuzzy matching enabled
- Nested tag support

### `comprehensive` - All Features
```lua
tags = require('pebble.completion.config').build_config('comprehensive')
```
- All tag extraction patterns
- Up to 2000 files
- 30-second cache TTL
- All features enabled
- Best for smaller repositories

### `obsidian` - Obsidian Vault Optimized
```lua
tags = require('pebble.completion.config').build_config('obsidian')
```
- Optimized for Obsidian-style tagging
- Supports nested tags with `/` separator
- YAML frontmatter array format

### `logseq` - Logseq Optimized
```lua
tags = require('pebble.completion.config').build_config('logseq')
```
- Simple inline tags only
- Optimized for Logseq workflows

## Usage

### Trigger Completion

1. **Automatic**: Type `#` and completion will trigger automatically (with nvim-cmp/blink.cmp)
2. **Manual**: Use `<C-t><C-t>` in insert mode to trigger tag completion
3. **Command**: `:PebbleComplete` for testing

### Supported Tag Formats

#### Inline Tags
```markdown
Here's a note about #productivity and #workflows/automation.
```

#### YAML Frontmatter Arrays
```yaml
---
tags: [productivity, workflows, automation]
categories: [work, personal]
---
```

#### YAML Frontmatter Lists
```yaml
---
tags:
  - productivity
  - workflows
  - automation
---
```

#### Nested Tags
```markdown
Using nested tags like #projects/work/client-a and #areas/health/fitness.
```

## Commands

| Command | Description |
|---------|-------------|
| `:PebbleTagsStats` | Show tag completion cache statistics |
| `:PebbleTagsSetup` | Run interactive setup wizard |
| `:PebbleCompletionRefresh` | Force refresh tag cache |

## Integration

### With nvim-cmp

The plugin automatically registers with nvim-cmp when available:

```lua
-- nvim-cmp setup (if you use it)
require('cmp').setup({
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
    { name = 'buffer' },
    { name = 'pebble_tags' },  -- Automatically added for markdown files
  })
})
```

### With blink.cmp

Automatic registration with blink.cmp when available:

```lua
-- blink.cmp will automatically detect and use the pebble_tags source
```

### Manual Integration (Fallback)

If you don't use a completion engine, you can use the omnifunc:

```lua
-- Set omnifunc for markdown files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.bo.omnifunc = 'pebble#completion#omnifunc'
  end
})
```

## Performance Tuning

### For Large Repositories

```lua
tags = require('pebble.completion.config').build_config('performance', {
  max_files_scan = 300,      -- Reduce file scan limit
  cache_ttl = 300000,        -- Increase cache TTL to 5 minutes
  max_completion_items = 20, -- Reduce completion items
})
```

### For Real-time Updates

```lua
tags = require('pebble.completion.config').build_config('balanced', {
  cache_ttl = 15000,         -- 15-second cache for fresh results
  async_extraction = true,   -- Always use async
})
```

### Custom Tag Patterns

```lua
tags = {
  -- Extract hashtags with emojis
  inline_tag_pattern = "#([a-zA-Z0-9_🏷️📝💡/-]+)",
  
  -- Support multiple frontmatter formats
  frontmatter_tag_pattern = 
    "tags:\\s*\\[([^\\]]+)\\]|" ..           -- [tag1, tag2]
    "tags:\\s*-\\s*([^\\n]+)|" ..            -- - tag1
    "keywords:\\s*\\[([^\\]]+)\\]|" ..       -- keywords: [...]  
    "topics:\\s*([^\\n,]+)",                 -- topics: topic1, topic2
}
```

## Troubleshooting

### Common Issues

1. **No completions appear**
   ```bash
   # Check if ripgrep is installed
   which rg
   
   # Check cache status
   :PebbleTagsStats
   ```

2. **Slow performance**
   ```lua
   -- Use performance preset
   tags = require('pebble.completion.config').build_config('performance')
   ```

3. **Tags not found**
   ```lua
   -- Verify your patterns match your tag format
   -- Run setup wizard for auto-detection
   :PebbleTagsSetup
   ```

### Debug Information

```lua
-- Get detailed cache information
:lua print(vim.inspect(require('pebble.completion').get_stats()))

-- Force cache refresh
:PebbleCompletionRefresh

-- Check ripgrep availability
:lua print(require('pebble.bases.search').has_ripgrep())
```

## Configuration Wizard

Run the interactive setup wizard to automatically detect and configure optimal settings:

```vim
:PebbleTagsSetup
```

The wizard will:
1. Detect your environment (Obsidian, Logseq, etc.)
2. Analyze your repository size
3. Suggest optimal configuration
4. Generate setup code for your init.lua

## API Reference

### Core Functions

```lua
local tags = require('pebble.completion.tags')

-- Setup with custom config
tags.setup(config)

-- Force cache refresh
tags.refresh_cache()

-- Get cache statistics
local stats = tags.get_cache_stats()

-- Get completion items for pattern
local items = tags.get_completion_items("productivity")

-- Trigger manual completion
tags.trigger_completion()
```

### Configuration Builder

```lua
local config_builder = require('pebble.completion.config')

-- Build preset configuration
local config = config_builder.build_config('balanced', {
  max_completion_items = 30
})

-- Validate configuration
local valid, errors = config_builder.validate_config(config)

-- Environment detection
local suggestions = config_builder.detect_environment()

-- Performance suggestions
local suggestions = config_builder.get_performance_suggestions(config)
```

## Examples

### Obsidian Vault Setup

```lua
require('pebble').setup({
  completion = {
    tags = require('pebble.completion.config').build_config('obsidian', {
      -- Custom overrides for your vault
      max_completion_items = 60,
      cache_ttl = 45000,  -- 45 seconds
    })
  }
})
```

### Academic Writing Setup

```lua
require('pebble').setup({
  completion = {
    tags = {
      inline_tag_pattern = "#([a-zA-Z0-9_-]+)",
      frontmatter_tag_pattern = 
        "tags:\\s*\\[([^\\]]+)\\]|" ..
        "keywords:\\s*\\[([^\\]]+)\\]|" ..
        "subjects:\\s*\\[([^\\]]+)\\]",
      file_patterns = { "*.md", "*.tex", "*.txt" },
      nested_tag_support = false,  -- Simple tags for papers
    }
  }
})
```

### Multi-language Setup

```lua
require('pebble').setup({
  completion = {
    tags = {
      -- Support international characters
      inline_tag_pattern = "#([\\w\\u00C0-\\u017F_/-]+)",
      file_patterns = { "*.md", "*.markdown", "*.org", "*.txt" },
      max_files_scan = 1500,
    }
  }
})
```

## Contributing

The tag completion system is designed to be extensible. Key areas for contribution:

1. **New tag patterns**: Add support for other markdown variants
2. **Performance optimizations**: Improve ripgrep query efficiency  
3. **UI enhancements**: Better completion item formatting
4. **Integration**: Support for additional completion engines

See the main pebble.nvim repository for contribution guidelines.
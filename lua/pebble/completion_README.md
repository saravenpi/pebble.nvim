# Pebble Markdown Link Completion

This module provides intelligent completion for markdown links in pebble.nvim. When you type `[` in a markdown file, it will suggest available markdown files in your project.

## Features

- **Trigger**: Completion is triggered when typing `[` in markdown files
- **Smart matching**: Matches both filenames and document titles
- **Title extraction**: Extracts titles from YAML frontmatter or H1 headers
- **Directory prioritization**: Prefers files in the same directory as the current file
- **Performance optimized**: Uses ripgrep for fast file discovery with caching
- **Multi-engine support**: Compatible with both nvim-cmp and blink.cmp

## Setup

The completion module is enabled by default when you setup pebble.nvim:

```lua
require('pebble').setup({
  enable_completion = true, -- default: true
  completion = {
    -- completion-specific options can go here
  }
})
```

To disable completion:

```lua
require('pebble').setup({
  enable_completion = false
})
```

## Compatibility

### nvim-cmp

If you have nvim-cmp installed, the completion source will be automatically registered for markdown files:

```lua
-- This is done automatically by pebble
require('cmp').setup.filetype('markdown', {
  sources = require('cmp').config.sources({
    { name = 'pebble_markdown_links', priority = 1000 },
  }, {
    { name = 'buffer' },
    { name = 'path' }
  })
})
```

### blink.cmp

If you have blink.cmp installed, the source will be registered automatically:

```lua
-- This is done automatically by pebble
require('blink.cmp').register_source('pebble_markdown_links', require('pebble.completion').blink_source)
```

## Usage

1. Open a markdown file
2. Type `[` to trigger completion
3. Start typing a filename or title to filter results
4. Select a completion item to insert the filename

### Examples

- `[` → Shows all available markdown files
- `[read` → Shows files matching "read" in filename or title
- `[My Document Title` → Shows files with matching titles

## Completion Items

Each completion item shows:
- **Label**: File title (if available) or filename
- **Detail**: Directory location and context
- **Documentation**: Full file path and metadata

Files in the same directory as the current file are prioritized and marked with "(same dir)".

## Commands

- `:PebbleCompletionStats` - Show completion cache statistics
- `:PebbleCompletionRefresh` - Manually refresh the completion cache

## Technical Details

### File Discovery
- Uses `ripgrep` for fast file discovery (fallback to vim.fs.find if not available)
- Searches from git root (fallback to current directory)
- Caches results for 30 seconds to improve performance

### Title Extraction
- Checks YAML frontmatter for `title:` field
- Falls back to first H1 header (`# Title`)
- Only reads first 20 lines for performance

### Performance
- Async completion to avoid blocking the UI
- Smart caching with TTL (30 seconds)
- Limits results to 50 items maximum
- Auto-invalidates cache when markdown files change

## Troubleshooting

If completion isn't working:

1. Ensure you have either nvim-cmp or blink.cmp installed
2. Check that pebble completion is enabled: `:PebbleCompletionStats`
3. Verify ripgrep is installed for optimal performance
4. Make sure you're in a markdown file (`.md` extension)

## Integration with Existing Configuration

The completion source plays nicely with your existing completion setup and won't interfere with other sources. It only activates in markdown files and only when typing after `[`.
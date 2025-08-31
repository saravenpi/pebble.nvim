# Pebble Wiki Link Completion

Pebble provides ultra-fast completion support for wiki links in markdown files. When you type `[[`, the plugin automatically suggests available notes based on their filenames, titles, and aliases.

## Features

- **Ultra-fast search**: Uses ripgrep to quickly discover all markdown files in your project
- **Smart caching**: Caches note metadata for 30 seconds to avoid repeated file operations
- **Fuzzy matching**: Advanced fuzzy matching algorithm that prioritizes:
  - Exact matches
  - Prefix matches
  - Word boundary matches
  - Consecutive character matches
- **Multiple matching sources**:
  - Filenames (without .md extension)
  - Note titles (from YAML frontmatter)
  - Aliases (from YAML frontmatter)
- **Completion engine support**:
  - nvim-cmp
  - blink.cmp
- **Wiki link patterns**:
  - `[[Note Name]]` - Simple wiki links
  - `[[Note Name|Display Text]]` - Wiki links with custom display text

## Configuration

### Basic Setup

```lua
require('pebble').setup({
    completion = {
        -- Enable/disable nvim-cmp source (default: true if nvim-cmp available)
        nvim_cmp = true,
        
        -- Enable/disable blink.cmp source (default: true if blink.cmp available)
        blink_cmp = true,
    }
})
```

### Disable Completion

```lua
require('pebble').setup({
    completion = false  -- Completely disable completion
})
```

## Completion Source Setup

### nvim-cmp

The pebble source automatically registers with nvim-cmp when available. Add it to your nvim-cmp sources:

```lua
require('cmp').setup({
    sources = {
        { name = 'pebble_wiki_links' },
        -- your other sources...
    }
})
```

### blink.cmp

For blink.cmp, the source is automatically registered when the plugin initializes:

```lua
require('blink.cmp').setup({
    sources = {
        completion = {
            enabled_providers = { 'pebble_wiki_links', 'lsp', 'path', 'snippets' }
        }
    }
})
```

## Usage

1. Open a markdown file
2. Type `[[` to trigger completion
3. Start typing the name of a note
4. Select from the fuzzy-matched suggestions
5. Press `Enter` or `Tab` to complete

The completion will search through:
- All markdown file names in your project
- Note titles from YAML frontmatter
- Note aliases from YAML frontmatter

## YAML Frontmatter Support

Pebble can extract titles and aliases from YAML frontmatter:

```yaml
---
title: "My Important Note"
aliases: 
  - "Important"
  - "VIP Note"
tags: ["work", "important"]
created: 2024-01-15
---

# My Important Note

Content goes here...
```

This note will be completed by typing any of:
- The filename (without .md)
- "My Important Note"
- "Important" 
- "VIP Note"

## Commands

- `:PebbleComplete` - Test completion in current wiki link context
- `:PebbleCompletionRefresh` - Manually refresh the completion cache
- `:PebbleCompletionStats` - Show completion cache statistics

## Performance

- Uses ripgrep for fast file discovery
- Caches note metadata for 30 seconds
- Limits cache to 2000 notes maximum
- Processes files in batches to avoid blocking the UI
- Only reads first 20 lines of each file for frontmatter parsing

## Troubleshooting

### No Completions Appearing

1. Ensure you're in a markdown file (`.md` extension)
2. Make sure you've typed `[[` to trigger the wiki link context
3. Check that ripgrep is installed: `rg --version`
4. Try `:PebbleComplete` to test manually
5. Check `:PebbleCompletionStats` to see cache status

### Performance Issues

1. Use `:PebbleCompletionStats` to check cache size
2. If you have thousands of markdown files, consider organizing them in subdirectories
3. The cache automatically limits to 2000 files for performance
4. Cache refreshes every 30 seconds or when files change

### Completion Not Working with Your Completion Engine

1. For nvim-cmp: Ensure the source is added to your sources list
2. For blink.cmp: Check that the provider is enabled
3. Both engines auto-register when pebble is setup, but may need manual configuration

## Integration Examples

### With Telescope

```lua
-- Use telescope to browse completions
vim.keymap.set('n', '<leader>fn', function()
    local completion = require('pebble.completion')
    local root_dir = completion.get_root_dir()
    local completions = completion.get_wiki_completions('', root_dir)
    
    require('telescope.pickers').new({}, {
        prompt_title = 'Wiki Notes',
        finder = require('telescope.finders').new_table({
            results = completions,
            entry_maker = function(entry)
                return {
                    value = entry.note_metadata.file_path,
                    display = entry.label,
                    ordinal = entry.label,
                    path = entry.note_metadata.file_path,
                }
            end,
        }),
        sorter = require('telescope.config').values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            require('telescope.actions').select_default:replace(function()
                require('telescope.actions').close(prompt_bufnr)
                local selection = require('telescope.actions.state').get_selected_entry()
                if selection then
                    vim.cmd('edit ' .. vim.fn.fnameescape(selection.value))
                end
            end)
            return true
        end,
    }):find()
end, { desc = 'Browse wiki notes' })
```

## API Reference

### completion.get_wiki_completions(query, root_dir)

Returns completion items for the given query.

**Parameters:**
- `query` (string): The search query
- `root_dir` (string): Directory to search for markdown files

**Returns:**
- Array of completion items with `label`, `insertText`, `detail`, etc.

### completion.is_wiki_link_context()

Checks if cursor is currently inside wiki link brackets.

**Returns:**
- `is_context` (boolean): True if inside `[[]]`
- `query` (string): Current query text

### completion.invalidate_cache()

Manually invalidate the completion cache to force refresh on next completion.
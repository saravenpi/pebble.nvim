# Ultra-Fast Tag Completion Usage Example

This document demonstrates how to set up and use the ultra-fast tag completion feature in pebble.nvim.

## Quick Setup

```lua
-- In your init.lua or pebble config
require('pebble').setup({
  completion = {
    tags = require('pebble.completion.config').build_config('balanced')
  }
})
```

## Usage Demo

### 1. Basic Tag Completion

Type `#` and completion will automatically trigger:

- `#prod` → suggests `#productivity`, `#projects`, `#programming`  
- `#work` → suggests `#workflows`, `#workplace`, `#work-life-balance`

### 2. Nested Tag Completion  

- `#proj` → suggests `#projects/work/client-a`, `#projects/personal/hobby`
- `#areas/` → suggests `#areas/health`, `#areas/learning`, `#areas/finance`

### 3. Fuzzy Matching

- `#aut` → finds `#automation`, `#authentication`, `#auto-save`
- `#nvp` → finds `#neovim-plugins`, `#nvim-productivity`

## Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `:PebbleTagsStats` | View cache statistics | Shows 247 tags cached |
| `:PebbleTestTags` | Run functionality tests | Validates extraction works |
| `:PebbleTagsSetup` | Interactive setup wizard | Auto-detects optimal config |
| `:PebbleCompletionRefresh` | Force cache refresh | Updates after bulk edits |

## Keybindings

- **Auto-trigger**: Type `#` in markdown files
- **Manual trigger**: `<C-t><C-t>` in insert mode  
- **Navigate completion**: `<C-n>`/`<C-p>` or arrow keys

## Performance Features

### Intelligent Caching
- 60-second cache TTL (configurable)
- Auto-refresh on file changes
- Ripgrep-powered extraction for speed

### Frequency-Based Scoring
- Most-used tags appear first
- Smart fuzzy matching
- Hierarchical tag organization

### Async Processing
- Non-blocking tag extraction
- Background cache updates
- Responsive completion UI

## Configuration Examples

### Obsidian Vault
```lua
completion = {
  tags = require('pebble.completion.config').build_config('obsidian', {
    cache_ttl = 45000,  -- 45 seconds for active vaults
    max_completion_items = 60
  })
}
```

### Large Repository (Performance Mode)
```lua
completion = {
  tags = require('pebble.completion.config').build_config('performance', {
    max_files_scan = 300,
    cache_ttl = 300000,  -- 5 minutes
    max_completion_items = 20
  })
}
```

### Academic Writing
```lua
completion = {
  tags = {
    inline_tag_pattern = "#([a-zA-Z0-9_-]+)",
    frontmatter_tag_pattern = "tags:\\s*\\[([^\\]]+)\\]|keywords:\\s*\\[([^\\]]+)\\]",
    file_patterns = { "*.md", "*.tex", "*.txt" },
    nested_tag_support = false  -- Simple flat tags for papers
  }
}
```

## Integration with Completion Engines

### nvim-cmp (Automatic)
```lua
-- The plugin automatically registers with nvim-cmp
-- No additional setup needed!
```

### blink.cmp (Automatic)
```lua
-- Also automatically registers with blink.cmp
-- Works out of the box!
```

### Manual (Fallback)
```lua
-- Set omnifunc if no completion engine available
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.bo.omnifunc = 'v:lua.require("pebble.completion").omnifunc'
  end
})
```

## Tag Formats Supported

### Inline Tags
```markdown
Working on #productivity and #automation projects.
Categorizing under #projects/work/client-a.
```

### YAML Frontmatter
```yaml
---
tags: [productivity, automation, workflows]
categories: [work, personal]
keywords: [efficiency, tools, systems]
---
```

### Mixed Formats
```yaml
---
tags: 
  - productivity
  - automation
---

# Content

Discussing #workflows and #time-management techniques.
```

## Troubleshooting

### No Completions Appear

1. **Check ripgrep installation**:
   ```bash
   which rg  # Should show ripgrep path
   ```

2. **Verify tag extraction**:
   ```vim
   :PebbleTagsStats  
   " Should show > 0 entries
   ```

3. **Check file patterns**:
   ```lua
   -- Ensure your files match the patterns
   file_patterns = { "*.md", "*.markdown", "*.txt" }
   ```

### Slow Performance

1. **Use performance preset**:
   ```lua
   tags = require('pebble.completion.config').build_config('performance')
   ```

2. **Reduce scan limits**:
   ```lua
   max_files_scan = 300,
   cache_ttl = 300000  -- 5 minutes
   ```

### Missing Tags

1. **Check tag patterns match your format**
2. **Run setup wizard**: `:PebbleTagsSetup`
3. **Force cache refresh**: `:PebbleCompletionRefresh`

## Testing Your Setup

Run the built-in test suite:

```vim
:PebbleTestTags
```

This will validate:
- ✅ Tag extraction from files
- ✅ Completion item generation  
- ✅ Fuzzy matching functionality
- ✅ Configuration validity
- ✅ Performance benchmarks

## Real-World Example

Here's how tag completion works in a typical note-taking session:

```markdown
---
tags: [meeting-notes, project-planning, team-coordination]
---

# Weekly Planning Meeting

## Action Items

- [ ] Review #project-alpha deliverables #deadline-friday
- [ ] Update #documentation for #api-changes
- [ ] Schedule #code-review with #team-backend

## Notes

Discussed #productivity improvements and #workflow optimization.
Need to implement #automation for #deployment-process.

Tagged with #areas/work #projects/q4-goals #status/in-progress
```

As you type `#`, the completion engine instantly suggests relevant tags based on your existing tag database, making note organization effortless and consistent!
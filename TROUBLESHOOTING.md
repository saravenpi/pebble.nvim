# Pebble.nvim Troubleshooting Guide

## Quick Fixes

### 🚨 Emergency Commands
If Pebble is causing issues, use these commands immediately:

```vim
:PebbleEmergencyDisable  " Disable all pebble functionality
:PebbleSafeMode         " Enable safe mode (navigation only)
:PebbleReset            " Reset all caches and state
```

### 📊 Diagnostic Commands
Run these to understand what's happening:

```vim
:PebbleHealth           " Complete system health check
:PebbleDiagnose         " Detailed diagnostic information
:PebbleStats           " Performance and cache statistics
:PebbleCompletionStats " Completion system status
```

---

## Common Issues and Solutions

### 1. Completion Not Working

#### Symptoms
- No completions appear when typing `[[` or `#`
- Error messages about completion sources
- Completion is slow or hangs

#### Solutions

**Check completion setup:**
```vim
:PebbleCompletionStatus
```

**Verify nvim-cmp configuration:**
```lua
-- Make sure pebble sources are registered
local cmp = require('cmp')
cmp.setup({
    sources = cmp.config.sources({
        { name = 'pebble_wiki_links', priority = 1000 },
        { name = 'pebble_tags', priority = 950 },
        -- ... other sources
    })
})
```

**Reset completion cache:**
```vim
:PebbleRefreshCache
```

### 2. Slow Performance / Hangs

#### Symptoms
- Neovim freezes when using completion
- Long delays when opening files
- High CPU usage

#### Solutions

**Check repository size:**
```vim
:PebbleStats
```

**If you have >1000 markdown files, use performance config:**
```lua
require('PRODUCTION_CONFIG').performance()
```

**Reduce cache size temporarily:**
```lua
require('pebble').setup({
    completion = {
        cache_max_size = 500,  -- Reduce from default
        cache_ttl = 120000,    -- Increase cache time
    }
})
```

**Emergency performance fix:**
```vim
:PebbleSafeMode
```

### 3. Ripgrep Issues

#### Symptoms
- "ripgrep not found" warnings
- Slow file discovery
- Search features not working

#### Solutions

**Install ripgrep:**
```bash
# macOS
brew install ripgrep

# Ubuntu/Debian
sudo apt install ripgrep

# Windows
choco install ripgrep

# Cargo (any platform)
cargo install ripgrep
```

**Verify installation:**
```bash
rg --version
```

**Configure path if needed:**
```lua
require('pebble').setup({
    search = {
        ripgrep_path = "/usr/local/bin/rg",  -- Adjust path
    }
})
```

### 4. Wiki Links Not Working

#### Symptoms
- `[[link]]` doesn't navigate
- "File not found" errors
- Links don't get created

#### Solutions

**Check if you're in a markdown file:**
```vim
:echo &filetype
" Should be 'markdown'
```

**Verify keymaps are set:**
```vim
:PebbleHistory  " Check navigation history
```

**Reset file cache:**
```vim
:PebbleBuildCache
```

### 5. Tag Completion Issues

#### Symptoms
- `#` doesn't trigger completion
- No tags found
- Tag extraction errors

#### Solutions

**Check tag configuration:**
```vim
:PebbleTagsStats
```

**Verify files contain tags:**
```markdown
<!-- Inline tags -->
This is a #sample tag

<!-- YAML frontmatter tags -->
---
tags: [sample, test, markdown]
---
```

**Reset tag cache:**
```vim
:PebbleTagsSetup  " Run setup wizard
```

---

## Configuration Issues

### 1. Conflicting Plugins

#### Symptoms
- Completion doesn't work with other plugins
- Keybinding conflicts
- Error messages about duplicate sources

#### Solutions

**Disable auto keymaps and set manually:**
```lua
require('pebble').setup({
    auto_setup_keymaps = false,
})

-- Set your own keymaps
vim.keymap.set('n', '<leader>gf', require('pebble').follow_link)
```

**Check for conflicting completion sources:**
```lua
-- Make sure names don't conflict
cmp.setup({
    sources = {
        { name = 'pebble_wiki_links' },  -- Not 'pebble'
        { name = 'pebble_tags' },        -- Separate source
    }
})
```

### 2. LazyVim/LunarVim/AstroVim Issues

#### Common setup for distributions:

**LazyVim:**
```lua
{
    "saravenpi/pebble.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "hrsh7th/nvim-cmp",
    },
    ft = "markdown",
    config = function()
        require('PRODUCTION_CONFIG').auto()
    end
}
```

**Custom cmp setup for distributions:**
```lua
-- In your cmp configuration
local cmp = require('cmp')
local config = cmp.get_config()
config.sources = cmp.config.sources({
    { name = 'pebble_wiki_links', priority = 1000 },
    { name = 'pebble_tags', priority = 950 },
}, config.sources or {})
cmp.setup(config)
```

---

## Performance Optimization

### 1. Large Repositories (>1000 files)

```lua
require('pebble').setup({
    search = {
        max_results = 500,      -- Limit search results
        timeout_ms = 10000,     -- 10 second timeout
    },
    completion = {
        cache_ttl = 120000,     -- 2 minute cache
        cache_max_size = 1000,  -- Reasonable limit
    }
})
```

### 2. Slow Systems

```lua
require('pebble').setup({
    completion = {
        nvim_cmp = {
            max_item_count = 20,  -- Fewer completion items
        },
        cache_ttl = 300000,      -- 5 minute cache
    }
})
```

### 3. Memory Optimization

```lua
require('pebble').setup({
    completion = {
        cache_max_size = 200,    -- Small cache
        cache_ttl = 60000,       -- 1 minute cache
    }
})
```

---

## Error Messages and Solutions

### "module 'pebble.completion.manager' not found"
**Cause:** Incomplete installation  
**Solution:** Reinstall the plugin or check your package manager

### "ripgrep not found - file discovery will be slower"
**Cause:** ripgrep not installed  
**Solution:** Install ripgrep using your system package manager

### "Failed to register completion sources"
**Cause:** nvim-cmp or blink.cmp not available  
**Solution:** Install completion framework or disable completion

### "No linked files found"
**Cause:** No markdown files with `[[]]` links  
**Solution:** Create some wiki-style links in your markdown files

### "Telescope is required for graph functionality"
**Cause:** telescope.nvim not installed  
**Solution:** Install telescope.nvim for graph features

---

## Safe Mode and Recovery

### When Everything Breaks

1. **Disable pebble completely:**
```vim
:PebbleEmergencyDisable
```

2. **Restart Neovim with minimal config:**
```bash
nvim -u NONE
```

3. **Use safe mode:**
```vim
:PebbleSafeMode
```

### Gradual Re-enable

1. **Start with basic setup:**
```lua
require('PRODUCTION_CONFIG').basic()
```

2. **Test navigation works**

3. **Upgrade to balanced:**
```lua
require('PRODUCTION_CONFIG').balanced()
```

4. **Test completion works**

5. **Upgrade to performance if needed:**
```lua
require('PRODUCTION_CONFIG').performance()
```

---

## Getting Help

### Information to Include in Bug Reports

Run these commands and include output:

```vim
:PebbleHealth
:PebbleDiagnose  
:version
:echo $PATH
```

Also include:
- Your Neovim version
- Your pebble configuration
- Steps to reproduce the issue
- Any error messages

### Useful Debug Commands

```vim
:messages                    " Recent error messages
:PebbleCompletionStatus     " Completion engine status
:lua print(vim.inspect(require('pebble').get_status()))
```

### Reset Everything

```vim
:PebbleReset                " Reset all caches
:PebbleEmergencyDisable     " Disable pebble
" Restart Neovim
:source ~/.config/nvim/init.lua  " Reload config
```

---

## Known Issues and Workarounds

### 1. Large Repository Performance
- **Issue:** Slow completion with >2000 files
- **Workaround:** Use `cache_max_size = 500` and longer `cache_ttl`

### 2. WSL/Windows Path Issues
- **Issue:** ripgrep path issues on Windows
- **Workaround:** Set explicit `ripgrep_path = "rg.exe"`

### 3. Telescope Conflicts
- **Issue:** Graph view doesn't work with custom telescope config
- **Workaround:** Ensure telescope is loaded before pebble

---

## Configuration Examples

### Minimal Working Config
```lua
require('pebble').setup({
    completion = false,  -- Disable completion
})
```

### Maximum Stability Config  
```lua
require('PRODUCTION_CONFIG').basic()
```

### Maximum Performance Config
```lua
require('PRODUCTION_CONFIG').performance()
```

---

This troubleshooting guide covers the most common issues. If you're still having problems, check the project's GitHub issues or create a new issue with the diagnostic information above.
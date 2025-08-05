# pebble.nvim 🪨

Obsidian-style markdown link navigation for Neovim.

## Features

- **Wiki-style Links**: Navigate using `[[file-name]]` syntax
- **Automatic File Creation**: Create files when following non-existent links
- **Interactive Graph View**: Visualize your markdown link network
- **Navigation History**: Go back and forward through your navigation
- **Link Management**: Create links from selected text
- **Performance Optimized**: Intelligent caching and git-aware file discovery

## Installation

### Using lazy.nvim
```lua
{
    dir = "path/to/pebble",
    config = function()
        require('pebble').setup({
            auto_setup_keymaps = true,
            global_keymaps = false
        })
    end
}
```

### Using Packer
```lua
use {
    'path/to/pebble',
    config = function()
        require('pebble').setup()
    end
}
```

## Usage

### Basic Navigation
1. Open a markdown file
2. Create links using `[[file-name]]` syntax
3. Place cursor on a link and press `<CR>` to follow it
4. Use `<Tab>` and `<S-Tab>` to jump between links
5. Use the graph view to explore your link network

### Creating Links
- Select text in visual mode
- Press `<leader>mc` to create a link, create the file, and navigate to it
- Press `<leader>ml` to create a link and create the file without navigation

### Graph View
- Press `:PebbleGraph` to open the interactive graph
- Use `j/k` or arrow keys to navigate
- Press `<CR>` to open a file
- Press `q` or `<Esc>` to close

## Commands

| Command | Description |
|---------|-------------|
| `:PebbleFollow` | Follow link under cursor |
| `:PebbleNext` | Next link in buffer |
| `:PebblePrev` | Previous link in buffer |
| `:PebbleBack` | Go back in history |
| `:PebbleForward` | Go forward in history |
| `:PebbleGraph` | Toggle graph view |
| `:PebbleHistory` | Show navigation history |
| `:PebbleStats` | Show cache statistics |
| `:PebbleCreateLinkAndNavigate` | Create link, file and navigate (visual mode) |
| `:PebbleCreateLinkAndFile` | Create link and file without navigation (visual mode) |

## Default Keymaps

### Markdown Files
- `<CR>` - Follow link under cursor
- `<Tab>` - Next link in buffer
- `<S-Tab>` - Previous link in buffer
- `<leader>mc` - Create link, file and navigate (visual mode)
- `<leader>ml` - Create link and file without navigation (visual mode)

### Optional Global Keymaps
Set `global_keymaps = true` in setup to enable:
- `<leader>mg` - Toggle graph view
- `<leader>mb` - Go back in history
- `<leader>mf` - Go forward in history

## Configuration

```lua
require('pebble').setup({
    -- Automatically set up keymaps for markdown files
    auto_setup_keymaps = true,

    -- Set up global keymaps (disabled by default)
    global_keymaps = false
})
```

### Custom Keymaps
To disable automatic keymaps and set your own:

```lua
require('pebble').setup({
    auto_setup_keymaps = false
})

-- Set custom keymaps
vim.keymap.set('n', 'gf', require('pebble').follow_link, { desc = 'Follow link' })
vim.keymap.set('n', '<leader>gg', require('pebble').toggle_graph, { desc = 'Toggle graph' })
vim.keymap.set('v', '<leader>cl', require('pebble').create_link_and_navigate, { desc = 'Create link and navigate' })
vim.keymap.set('v', '<leader>cf', require('pebble').create_link_and_file, { desc = 'Create link and file' })
```

### Global Keymaps
Enable global keymaps for non-markdown files:

```lua
require('pebble').setup({
    global_keymaps = true  -- Enables <leader>mg, <leader>mb, <leader>mf globally
})
```

## Link Formats Supported

- `[[wiki-style]]` - Obsidian-style links
- `[text](file.md)` - Standard markdown links
- `[text](https://url.com)` - External URLs (opens in browser)

## Compatibility

Pebble works excellently with [**markview.nvim**](https://github.com/OXY2DEV/markview.nvim) and other markdown rendering plugins. The link navigation functionality is completely independent of how markdown is displayed, so you can enjoy beautiful rendered markdown while still having full Obsidian-style linking capabilities.

## Advanced Features

### Visual Link Creation
- **Create and Navigate**: Select text, press `<leader>mc` to create a `[[link]]`, create the file, and navigate to it
- **Create Only**: Select text, press `<leader>ml` to create a `[[link]]` and the file without navigation
- **Smart Filename Cleaning**: Removes invalid characters while preserving spaces and accents
- **Duplicate Prevention**: Checks for existing files before creating new ones

### Navigation System
- **History Tracking**: Automatic back/forward navigation with `<leader>mb` and `<leader>mf`
- **Smart Link Jumping**: Use `<Tab>` and `<Shift-Tab>` to move between links in a file
- **Fallback Behavior**: `<CR>` falls back to default behavior when not on a link

### Interactive Graph View
- **Visual Network**: See all connected files in a clean, interactive interface
- **Keyboard Navigation**: Use `j/k` or arrows to navigate, `Enter` to open files
- **Missing File Detection**: Clearly shows which links point to non-existent files
- **Performance Optimized**: Cached results with smart invalidation

### Performance Features
- **Intelligent Caching**: File discovery results are cached and invalidated automatically
- **Git-Aware**: Uses git root as the search base when available
- **Limited Scanning**: Prevents performance issues in large repositories (200 file limit)
- **Graph Caching**: Graph view results are cached with 5-second TTL
- **Lazy Loading**: Caches are built only when needed, not on startup

## License

MIT

# pebble.nvim 🪨

<a href="https://dotfyle.com/plugins/saravenpi/pebble.nvim">
    <img src="https://dotfyle.com/plugins/saravenpi/pebble.nvim/shield?style=flat" />
</a>

Obsidian-style markdown link navigation and database views for Neovim.

## Features

- **Wiki-style Links**: Navigate using `[[file-name]]` syntax
- **Automatic File Creation**: Create files when following non-existent links
- **Interactive Graph View**: Visualize your markdown link network
- **Navigation History**: Go back and forward through your navigation
- **Link Management**: Create links from selected text
- **Performance Optimized**: Intelligent caching and git-aware file discovery
- **Bases Support**: Create and view Obsidian-compatible database views from markdown files
- **Heading Management**: Increase/decrease heading levels with `+`/`-`
- **YAML Frontmatter**: Initialize and manage YAML headers

## Installation

### Dependencies

- **Required**: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - Used for bases functionality
- **Optional**: [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) - Enhanced syntax highlighting

### Using lazy.nvim
```lua
{
    "saravenpi/pebble.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        -- Optional: enhanced treesitter support
        -- "nvim-treesitter/nvim-treesitter",
    },
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
    'saravenpi/pebble.nvim',
    requires = {
        'nvim-telescope/telescope.nvim',
    },
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
5. Use `<leader>mp` and `<leader>mn` to navigate history
6. Use the graph view to explore your link network

### Creating Links
- Select text in visual mode
- Press `<leader>mc` to create a link, create the file, and navigate to it
- Press `<leader>ml` to create a link and create the file without navigation

### Graph View
- Press `<leader>mg` to open the interactive graph
- Press `<leader>mv` to open the enhanced visual graph with ASCII art
- Use `j/k` or arrow keys to navigate
- Press `<CR>` to open a file
- Press `q` or `<Esc>` to close

### Database Views (Bases)
- Create `.base` files with YAML configuration
- Press `<leader>mB` to list all available bases
- Press `<leader>bo` when editing a `.base` file to preview it
- Navigate with `j/k`, `↑/↓`, `G/gg`
- Press `<CR>` to open selected file
- Press `r` to refresh the cache
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
| `:PebbleVisualGraph` | Toggle enhanced visual graph view |
| `:PebbleHistory` | Show navigation history |
| `:PebbleStats` | Show cache statistics |
| `:PebbleToggleChecklist` | Toggle markdown checklist/todo item |
| `:PebbleCreateLinkAndNavigate` | Create link, file and navigate (visual mode) |
| `:PebbleCreateLinkAndFile` | Create link and file without navigation (visual mode) |
| `:PebbleInitHeader` | Initialize YAML header if not present |
| `:PebbleIncreaseHeading` | Increase markdown heading level |
| `:PebbleDecreaseHeading` | Decrease markdown heading level |
| `:PebbleBase [path]` | Open a base view (current file if no path) |
| `:PebbleBases` | List and select available base files |

## Default Keymaps

### Markdown Files
- `<CR>` - Follow link under cursor
- `<Tab>` - Next link in buffer
- `<S-Tab>` - Previous link in buffer
- `<Ctrl+t>` or `<leader>mt` - Toggle markdown checklist/todo item
- `<leader>mg` - Toggle graph view
- `<leader>mv` - Toggle visual graph view
- `<leader>mc` - Create link, file and navigate (visual mode)
- `<leader>ml` - Create link and file without navigation (visual mode)
- `<leader>mh` - Initialize YAML header
- `+` - Increase heading level
- `-` - Decrease heading level

### Base Files (.base)
- `<leader>bo` - Open current base view

### Base View Navigation
When viewing a base:
- `j`/`k` or `↑`/`↓` - Navigate rows
- `G` - Go to last item
- `gg` - Go to first item
- `<CR>` - Open selected file
- `r` - Refresh cache
- `q` or `<Esc>` - Close view

### Optional Global Keymaps
Set `global_keymaps = true` in setup to enable:
- `<leader>mg` - Toggle graph view
- `<leader>mv` - Toggle visual graph view
- `<leader>mp` - Go to previous in navigation history
- `<leader>mn` - Go to next in navigation history
- `<leader>mB` - List available bases
- `<leader>mb` - Open current base view

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
vim.keymap.set('n', '<leader>gv', require('pebble').toggle_visual_graph, { desc = 'Toggle visual graph' })
vim.keymap.set('v', '<leader>cl', require('pebble').create_link_and_navigate, { desc = 'Create link and navigate' })
vim.keymap.set('v', '<leader>cf', require('pebble').create_link_and_file, { desc = 'Create link and file' })
```

### Global Keymaps
Enable global keymaps for non-markdown files:

```lua
require('pebble').setup({
    global_keymaps = true  -- Enables global keymaps for all file types
})
```

## Link Formats Supported

- `[[wiki-style]]` - Obsidian-style links
- `[text](file.md)` - Standard markdown links
- `[text](https://url.com)` - External URLs (opens in browser)

## Compatibility

Pebble works excellently with [**markview.nvim**](https://github.com/OXY2DEV/markview.nvim) and other markdown rendering plugins. The link navigation functionality is completely independent of how markdown is displayed, so you can enjoy beautiful rendered markdown while still having full Obsidian-style linking capabilities.

## Advanced Features

### Bases (Database Views)
Create Obsidian-compatible database views from your markdown files using `.base` files. Fully compatible with Obsidian's bases feature introduced in 2025.

**Note**: Bases functionality uses Telescope for the UI. Make sure telescope.nvim is installed and configured.

**Example base file (tasks.base):**
```yaml
# Filter which files to include
filters:
  and:
    - status != "done"
    - status != "cancelled"

# Create computed properties
formulas:
  days_until_due: 'due and tonumber(os.difftime(date(due), os.time()) / 86400) or nil'
  priority_level: 'priority == "high" and "🔴" or priority == "medium" and "🟡" or "🟢"'
  status_icon: 'status == "todo" and "⏳" or status == "in-progress" and "🔄" or "✅"'

# Display names for columns
display:
  name:
    displayName: "Task"
  formula.status_icon:
    displayName: "📊"
  formula.days_until_due:
    displayName: "Days Left"

# Define views
views:
  - type: table
    name: "Active Tasks"
    filters:
      and:
        - status != "done"
    order:
      - priority
      - due
    limit: 50
```

**Supported Features:**
- **Filters**: Complex logical operations (`and`, `or`, `not`)
- **Formulas**: Dynamic computed properties with date math, conditionals, string operations
- **Display Names**: Custom column headers for better readability
- **Views**: Table view with sorting, filtering, and limits
- **Functions**: `date()`, `now()`, `if()`, `concat()`, `length()`, and more
- **Obsidian Compatibility**: Supports both old and new Obsidian filter syntax

### Visual Link Creation
- **Create and Navigate**: Select text, press `<leader>mc` to create a `[[link]]`, create the file, and navigate to it
- **Create Only**: Select text, press `<leader>ml` to create a `[[link]]` and the file without navigation
- **Smart Filename Cleaning**: Removes invalid characters while preserving spaces and accents
- **Duplicate Prevention**: Checks for existing files before creating new ones

### Navigation System
- **History Tracking**: Automatic back/forward navigation with `<leader>mp` (previous) and `<leader>mn` (next)
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
- **Base Caching**: Base queries are cached for fast repeated access
- **Lazy Loading**: Caches are built only when needed, not on startup

## License

MIT

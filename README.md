# pebble.nvim 🪨

<a href="https://dotfyle.com/plugins/saravenpi/pebble.nvim">
    <img src="https://dotfyle.com/plugins/saravenpi/pebble.nvim/shield?style=flat" />
</a>

**Production-Ready Obsidian-style Markdown Link Navigation for Neovim**

Transform your Neovim into a powerful knowledge management system with wiki-style links, intelligent completion, and database views.

## ✨ Key Features

- **🔗 Wiki-style Links**: Navigate using `[[file-name]]` syntax with automatic file creation
- **🧠 Intelligent Completion**: Ultra-fast tag (`#`), wiki link (`[[`), and markdown link completion
- **📊 Interactive Graph View**: Visualize your markdown link network with telescope integration  
- **⚡ Performance Optimized**: Sub-second file discovery with ripgrep, intelligent caching, async processing
- **🗄️ Database Views (Bases)**: Create and view Obsidian-compatible database views with complex filtering
- **📝 Link Management**: Create links from selected text with smart filename cleaning
- **🔄 Navigation History**: Seamless back/forward navigation through your knowledge base
- **⚙️ Production Ready**: Comprehensive error handling, diagnostics, and emergency recovery options

## 🚀 Version 2.0 - December 2024

**Major Performance & Completion Overhaul**
- **10-20x faster** file discovery and completion with ripgrep integration
- **Production-grade stability** with comprehensive testing and error handling
- **Intelligent auto-configuration** that adapts to your repository size  
- **Emergency safety commands** for troubleshooting and recovery
- **Enhanced completion system** with tag and wiki link support

## Installation

### Dependencies

- **Required**: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - Used for bases functionality
- **Required**: [ripgrep](https://github.com/BurntSushi/ripgrep) - Fast file search for completion and search features
- **Optional**: [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) - Enhanced syntax highlighting
- **Optional**: [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) - Completion framework support
- **Optional**: [blink.cmp](https://github.com/Saghen/blink.cmp) - Alternative completion framework support

#### Installing ripgrep

**macOS** (via Homebrew):
```bash
brew install ripgrep
```

**Ubuntu/Debian**:
```bash
sudo apt install ripgrep
```

**Fedora**:
```bash
sudo dnf install ripgrep
```

**Arch Linux**:
```bash
sudo pacman -S ripgrep
```

**Windows** (via Chocolatey):
```bash
choco install ripgrep
```

**Cargo** (cross-platform):
```bash
cargo install ripgrep
```

### Using lazy.nvim

**Production-Ready Setup (Recommended):**
```lua
{
    "saravenpi/pebble.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "hrsh7th/nvim-cmp", -- Optional: for completion support
        -- "Saghen/blink.cmp", -- Alternative: blink.cmp support
    },
    ft = "markdown", -- Load only for markdown files
    config = function()
        -- Auto-configure based on your repository size and setup
        require('PRODUCTION_CONFIG').auto()
    end
}
```

**Manual Setup (Advanced Users):**
```lua
{
    "saravenpi/pebble.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "hrsh7th/nvim-cmp",
    },
    config = function()
        require('pebble').setup({
            auto_setup_keymaps = true,
            global_keymaps = false,
            completion = {
                nvim_cmp = true,  -- Enable nvim-cmp integration
                blink_cmp = false, -- Disable blink.cmp (or true to enable)
            },
            search = {
                ripgrep_path = "rg", -- Path to ripgrep executable
            },
        })
        
        -- Add pebble completion sources to nvim-cmp
        local cmp = require('cmp')
        cmp.setup({
            sources = cmp.config.sources({
                { name = "pebble_wiki_links", priority = 1000 }, -- Wiki links [[
                { name = "pebble_tags", priority = 950 },        -- Tags #
                { name = 'nvim_lsp' },
                { name = 'buffer' },
                { name = 'path' },
            })
        })
    end
}
```

**Advanced setup with detailed configuration:**
```lua
{
    "saravenpi/pebble.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "hrsh7th/nvim-cmp",
    },
    config = function()
        require('pebble').setup({
            auto_setup_keymaps = true,
            global_keymaps = false,
            completion = {
                nvim_cmp = {
                    enabled = true,
                    priority = 100,
                    max_item_count = 50,
                    trigger_characters = { "[", "#" },
                },
                blink_cmp = {
                    enabled = false,
                    priority = 100,
                    max_item_count = 50,
                },
                cache_ttl = 30000,     -- Cache TTL in milliseconds
                cache_max_size = 2000, -- Maximum cached items
            },
            search = {
                ripgrep_path = "rg",
                max_results = 1000,
                timeout_ms = 5000,
            }
        })
        
        -- Configure nvim-cmp with pebble sources
        local cmp = require('cmp')
        cmp.setup({
            sources = cmp.config.sources({
                { name = "pebble_wiki_links", priority = 1000 },
                { name = "pebble_tags", priority = 950 },
                { name = 'nvim_lsp' },
                { name = 'luasnip' },
                { name = 'buffer' },
                { name = 'path' },
            })
        })
    end
}
```

**With blink.cmp:**
```lua
{
    "saravenpi/pebble.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "Saghen/blink.cmp",
    },
    config = function()
        require('pebble').setup({
            completion = {
                blink_cmp = {
                    priority = 100,
                    max_item_count = 50,
                }
            }
        })
    end
}
```

**Minimal setup (no completion):**
```lua
{
    "saravenpi/pebble.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
    },
    config = function()
        require('pebble').setup({
            completion = false -- Disable completion features
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
        'hrsh7th/nvim-cmp', -- Optional
    },
    config = function()
        require('pebble').setup()
        
        -- Setup nvim-cmp source if using nvim-cmp
        local cmp = require('cmp')
        cmp.setup({
            sources = cmp.config.sources({
                { name = 'nvim_lsp' },
                { name = 'pebble' },
                { name = 'buffer' },
            })
        })
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

### Smart Completion

Pebble provides three types of intelligent completion:

#### 1. Wiki Link Completion (`[[`)
- **Trigger**: Type `[[` in any markdown file
- **Features**: 
  - Advanced fuzzy matching against filenames, titles, and aliases
  - YAML frontmatter title and alias support
  - Supports both `[[Note Name]]` and `[[Note Name|Display Text]]` formats
  - Ultra-fast ripgrep-powered file discovery
  - Intelligent caching with 30-second TTL

#### 2. Tag Completion (`#`)
- **Trigger**: Type `#` in any markdown file  
- **Features**:
  - Extracts tags from both inline (`#tag`) and YAML frontmatter
  - Supports nested tags (`#category/subcategory`)
  - Frequency-based ranking with fuzzy matching
  - Immediate response with intelligent caching

#### 3. Markdown Link Completion (`[`)
- **Trigger**: Type `](` for markdown links
- **Features**:
  - Relative file path completion
  - Title extraction from YAML frontmatter and headers
  - Context-aware suggestions prioritizing nearby files

#### Performance Characteristics
- **Ripgrep Integration**: Sub-second file discovery for large repositories
- **Intelligent Caching**: 30-second TTL with automatic invalidation
- **Async Processing**: Non-blocking UI with batch processing
- **Scalability**: Efficiently handles 2000+ markdown files
- **Fallback Support**: Works without ripgrep using vim.fs.find

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
| `:PebbleSearch <pattern>` | Search in markdown files using ripgrep |
| `:PebbleComplete` | Test wiki link completion in current context |
| `:PebbleCompletionStats` | Show completion cache statistics |
| `:PebbleCompletionRefresh` | Refresh completion cache |
| `:PebbleDiagnose` | Run comprehensive system diagnostics |
| `:PebbleReset` | Reset all caches and internal state |
| `:PebbleBuildCache` | Build file cache with progress notification |
| `:PebbleBaseAsync <path>` | Open base view asynchronously (non-blocking) |
| `:PebbleTagsSetup` | Interactive setup wizard for tag completion |
| `:PebbleTagsStats` | Show tag completion statistics |
| `:PebbleTestTags` | Run tag completion system tests |

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
    global_keymaps = false,

    -- Completion configuration
    completion = {
        -- Enable nvim-cmp integration (auto-detected if not specified)
        nvim_cmp = {
            priority = 100,
            max_item_count = 50,
            trigger_characters = { "[", "(" },
        },
        
        -- Enable blink.cmp integration (auto-detected if not specified)
        blink_cmp = {
            priority = 100,
            max_item_count = 50,
            trigger_characters = { "[", "(" },
        },
    }
})
```

### Completion Features

Pebble provides intelligent completion for markdown files with three types of completions:

1. **Wiki Link Completion** (`[[file-name]]`)
   - Auto-completes file names when typing `[[`
   - Shows available markdown files in your project
   - Uses ripgrep for fast file discovery

2. **File Path Completion** (`[text](path)`)
   - Auto-completes file paths when typing `](`
   - Provides relative paths to markdown files
   - Optimized for current directory context

3. **Text Search Completion**
   - Searches content across all markdown files using ripgrep
   - Triggered when typing 2+ character words
   - Shows matching text with file context

### Performance Characteristics

- **Fast File Discovery**: Uses ripgrep for sub-second file enumeration
- **Intelligent Caching**: 30-second TTL cache for file lists and completions
- **Context-Aware**: Only activates in markdown files
- **Minimal Resource Usage**: Lazy-loaded modules and efficient search patterns
- **Async Processing**: Non-blocking operations for large repositories
- **Smart Fallbacks**: Graceful degradation when ripgrep is unavailable

## Recent Updates & Improvements

### v2.1.0 - Performance & Completion Overhaul
- **🚀 Major Performance Improvements**: 10-20x faster file discovery and bases loading
- **✨ Enhanced Completion System**: Ultra-fast tag (`#`), wiki link (`[[`), and markdown link (`[`) completion
- **⚡ Ripgrep Integration**: All search operations now use ripgrep for maximum speed
- **🔧 Async Processing**: Bases now load asynchronously with smart caching
- **🛠️ Better Error Handling**: Comprehensive diagnostics and recovery mechanisms
- **📊 Monitoring Tools**: Added diagnostic commands and performance monitoring
- **🔄 Configuration Flexibility**: Support for both boolean and detailed table configurations

### Configuration Migration
The plugin now supports both simple boolean and detailed table configurations:

```lua
-- Simple configuration (recommended)
completion = {
    nvim_cmp = true,  -- Enable nvim-cmp integration
    blink_cmp = false, -- Disable blink.cmp
}

-- Advanced configuration (optional)
completion = {
    nvim_cmp = {
        enabled = true,
        priority = 100,
        max_item_count = 50,
    },
    blink_cmp = {
        enabled = false,
    },
}
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

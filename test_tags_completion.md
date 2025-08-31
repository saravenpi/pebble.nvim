# Tag Completion Test File

This file is for testing the improved tag completion system in pebble.nvim.

## Test Cases

### Inline Tags
Here are some inline tags to test completion:
- #productivity
- #neovim/plugins
- #markdown/notes
- #work/projects
- #learning/lua
- #development/tools
- #obsidian/features

### YAML Frontmatter Tags
```yaml
---
title: Test File for Tag Completion
tags: [productivity, neovim, markdown, development]
aliases: [test-file, tag-test]
created: 2025-01-31
---
```

### Mixed Format YAML Tags
```yaml
---
title: Mixed Tags Format
tags:
  - development
  - lua
  - neovim
  - completion
  - testing
---
```

### Test Areas

Type # to trigger tag completion:

1. Basic completion: #
2. Partial matching: #prod
3. Nested tags: #neovim/
4. Case insensitive: #PROD

## Expected Behavior

1. # should immediately trigger tag completion
2. Tags should be extracted from both inline usage and YAML frontmatter
3. Completion should show frequency information
4. Nested tags should have proper documentation
5. Fuzzy matching should work for partial queries

## Performance Test

The system should handle large repositories with many markdown files efficiently using:
- Ripgrep for fast tag extraction
- Proper caching with TTL
- Asynchronous processing to avoid blocking UI
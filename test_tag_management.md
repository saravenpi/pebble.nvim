# Tag Management Test File

This file demonstrates the tag management features in pebble.nvim.

## Frontmatter Tags
---
title: Tag Management Demo
tags: [demo, test, pebble, frontmatter-example]
aliases: [tag-demo, test-tags]
---

## Inline Tags

This file contains various inline tags for testing:

- Project management: #project #work #management
- Development: #coding #development #javascript #lua
- Personal: #personal #notes #ideas
- Nested tags: #work/project/urgent #development/web/frontend

## Tag Management Commands

### Available Commands:
1. `:PebbleAddTag` - Add a tag to the current file
2. `:PebbleShowTags` - Show all tags in current file (telescope UI)
3. `:PebbleFindTag` - Find files containing a specific tag

### Keymaps:
- `<leader>mta` - Add tag to current file
- `<leader>mts` - Show tags in current file  
- `<leader>mtf` - Find files with tag

## Testing Instructions

1. **Add Tags**:
   - Press `<leader>mta` in normal mode
   - Type a new tag name (autocomplete available)
   - Tag will be added to frontmatter

2. **View Tags**:
   - Press `<leader>mts` to see all tags in this file
   - Select a tag to find other files with the same tag

3. **Search Tags**:
   - Press `<leader>mtf` to search for files by tag
   - Enter tag name or select from autocomplete
   - Browse results with telescope

## Mixed Content

Some regular text with #mixed-tags and normal content.

Links to other files: [[another-note]] and [external](https://example.com)

More tags: #testing #final-tag
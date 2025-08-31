---
title: Frontmatter Tag Examples
tags: 
  - frontmatter
  - yaml
  - metadata
  - testing
  - completion-system
categories: [development, documentation, testing]
keywords: [pebble, neovim, tags, completion]
topics: markdown, note-taking, knowledge-management
aliases: 
  - "Tag Examples"
  - "YAML Tags Demo"
created: 2024-12-31
updated: 2024-12-31
---

# YAML Frontmatter Tag Examples

This document demonstrates different YAML frontmatter formats that the tag completion system should recognize.

## Array Format Tags

The frontmatter above uses standard YAML array formats:

```yaml
tags: [frontmatter, yaml, metadata, testing]
categories: [development, documentation, testing]
```

## List Format Tags

Some documents prefer the list format:

```yaml
tags:
  - frontmatter  
  - yaml
  - metadata
  - testing
  - completion-system
```

## Mixed Inline and Frontmatter

This document combines frontmatter tags with inline tags like #performance and #caching for comprehensive tag coverage.

## Content with Various Tag Styles

The content discusses #yaml-processing and #metadata-extraction from markdown files. Key aspects include:

1. **Parser flexibility**: Supporting both #array-format and #list-format
2. **Performance**: Efficient #frontmatter-parsing without reading entire files
3. **Compatibility**: Working with #obsidian and #logseq formats

## Complex Nested Examples

Some advanced tagging patterns:

- Inline: #system/completion/tags #workflow/documentation/writing
- Mixed with frontmatter topics: the system handles #knowledge-management alongside YAML-defined categories

## Integration Testing

This file tests the integration between:
- YAML frontmatter extraction (#metadata-extraction)
- Inline tag recognition (#tag-parsing) 
- Completion system caching (#performance-optimization)
- Multiple file format support (#markdown-variants)
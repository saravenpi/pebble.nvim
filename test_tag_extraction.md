---
title: Test Tag Extraction
tags: [frontmatter-tag, yaml-example, test]
aliases: [extraction-test]
---

# Tag Extraction Test

This file tests tag extraction functionality.

## Inline Tags

Simple tags: #simple #test #a #extraction
Nested tags: #work/urgent #dev/lua/nvim
Hyphenated: #multi-word #tag-example
Underscored: #under_scored #tag_test

## Edge Cases

Tags with numbers: #tag1 #version2 #test123
Mixed: #work/project-2023 #dev_env/setup

## Not Tags

These should not be extracted:
- #123 (starts with number)
- # (just hash)
- #-invalid (starts with dash)

Regular text with some #valid-tags mixed in.
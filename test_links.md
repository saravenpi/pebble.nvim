# Test Link Navigation and Highlighting

Here are different types of links to test:

## HTTPS/HTTP Links (should be highlighted and navigable with Enter/Tab)
- Regular HTTPS: https://www.google.com
- HTTP link: http://example.com
- HTTPS with path: https://github.com/user/repo/issues/123
- HTTPS with query: https://search.example.com?q=test&type=all
- Complex URL: https://api.example.com/v1/users/123/profile?include=posts,comments&format=json

## Obsidian Links (navigable with Enter/Tab)
- [[test-note]] - Will create file if doesn't exist
- [[another-file|Display Text]] - Link with custom display text

## Markdown Links (navigable with Enter/Tab)
- [Google](https://www.google.com) - External link
- [Local File](local-file.md) - Local markdown file

## Tags (highlighted)
#test #markdown #links #web/development

## Testing Instructions
1. Press Enter on any link to follow/open it
2. Use Tab/Shift+Tab to navigate between all link types
3. All HTTP/HTTPS links should be highlighted
4. All tags should be highlighted

Regular text should not be highlighted.
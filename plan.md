# Fix: Preserve HTML formatting in attributed strings

## Problem

We're losing HTML formatting at multiple stages:

1. **BlockParser** only recognizes `p`, `h1-h6`, `li`, `blockquote`, `pre` - images, divs, and other content are ignored
2. **createStyledText()** throws away all HTML, using only `block.textContent` (plain text)
3. Inline formatting (`<b>`, `<i>`, `<em>`, `<a>`, etc.) is completely lost

Example: The Hitchhiker's Guide cover uses `<div><svg><image xlink:href="..."></svg></div>` which is never parsed into a block, and even if it were, the image path wouldn't be extracted.

## Design Principles

- **Blocks remain the fundamental unit** - Block IDs are used throughout for position tracking, navigation, search results, etc. This doesn't change.
- **Better rendering of block content** - Parse `block.htmlContent` properly instead of using plain text
- **Extensible pattern matching** - Easy to add support for new HTML patterns without major refactoring
- **Performance matters** - Avoid WebKit's slow NSAttributedString HTML init; use lightweight parsing

## Proposed Changes

### Step 1: Expand BlockParser to recognize more content types

**File:** `BlockParser.swift`

Add detection for:
- `<img>` tags (standalone images)
- `<svg>` containing `<image>` elements
- `<div>` elements that contain meaningful content (images, formatted text)
- `<figure>` and `<figcaption>` elements

```swift
// Add to blockTags or handle separately
private static let imageTags: Set<String> = ["img", "svg", "figure"]

// New method to find image blocks
private func findImageBlocks(in html: String, spineItemId: String, startingOrdinal: Int) -> [Block] {
    var blocks: [Block] = []

    // Pattern for <img src="...">
    let imgPattern = #"<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*/?>"#

    // Pattern for <svg>...<image xlink:href="...">...</svg>
    let svgPattern = #"<svg[^>]*>[\s\S]*?<image[^>]*xlink:href\s*=\s*["']([^"']+)["'][^>]*>[\s\S]*?</svg>"#

    // Pattern for <div> containing only image content
    let divImagePattern = #"<div[^>]*>\s*(<img[^>]*>|<svg[^>]*>[\s\S]*?</svg>)\s*</div>"#

    // ... match and create blocks with type .image
}
```

### Step 2: Create lightweight HTML → AttributedString parser

**File:** `HTMLToAttributedString.swift`

Replace `createStyledText()` with `parseBlockHTML()` that actually parses the HTML:

```swift
private func parseBlockHTML(_ block: Block) -> NSAttributedString {
    let html = block.htmlContent
    let result = NSMutableAttributedString()

    // Base attributes from block type
    var baseAttrs = attributesForBlockType(block.type)

    // Parse inline elements
    // This is a simplified recursive descent - real implementation would be more robust
    parseInlineContent(html, into: result, baseAttributes: baseAttrs)

    return result
}

private func parseInlineContent(_ html: String, into result: NSMutableAttributedString, baseAttributes: [NSAttributedString.Key: Any]) {
    // Handle these inline patterns:
    // <b>, <strong> → add .font with bold trait
    // <i>, <em> → add .font with italic trait
    // <a href="..."> → add .link attribute
    // <img src="..."> → add NSTextAttachment
    // <span class="..."> → map known classes to attributes
    // Plain text → append with base attributes
}
```

### Step 3: Extract image paths from multiple formats

**File:** `HTMLToAttributedString.swift`

Update `extractImagePath()` to handle all image formats:

```swift
private func extractImagePath(from html: String) -> String? {
    // Standard img src
    if let path = matchFirst(#"<img[^>]*src\s*=\s*["']([^"']+)["']"#, in: html) {
        return path
    }

    // SVG xlink:href
    if let path = matchFirst(#"xlink:href\s*=\s*["']([^"']+)["']"#, in: html) {
        return path
    }

    // SVG href (modern syntax without xlink prefix)
    if let path = matchFirst(#"<image[^>]*href\s*=\s*["']([^"']+)["']"#, in: html) {
        return path
    }

    return nil
}
```

### Step 4: Support inline images via NSTextAttachment

For images that appear inline (not full-page), embed them in the attributed string:

```swift
private func createImageAttachment(path: String) -> NSTextAttachment? {
    guard let imageData = imageCache[path],
          let image = UIImage(data: imageData) else {
        return nil
    }

    let attachment = NSTextAttachment()
    attachment.image = image

    // Scale to fit text line height or max width
    let maxWidth: CGFloat = 300
    let scale = min(1.0, maxWidth / image.size.width)
    attachment.bounds = CGRect(
        x: 0, y: 0,
        width: image.size.width * scale,
        height: image.size.height * scale
    )

    return attachment
}
```

## Files to Modify

1. **`BlockParser.swift`**
   - Add `findImageBlocks()` method
   - Call it from `parse()` and `parseWithAnnotatedHTML()`
   - Expand pattern matching for divs/figures with content

2. **`HTMLToAttributedString.swift`**
   - Replace `createStyledText()` with `parseBlockHTML()`
   - Add inline formatting support (bold, italic, links)
   - Update `extractImagePath()` for SVG/xlink
   - Add `createImageAttachment()` for inline images

3. **`Block.swift`** (if needed)
   - Consider adding more BlockTypes: `.figure`, `.divImage`, etc.
   - Or keep `.image` and let the HTML content distinguish subtypes

4. **`EPUBLoader.swift`** (verify)
   - Ensure images referenced by `xlink:href` are cached

## Implementation Order

1. First: Update `extractImagePath()` to handle `xlink:href` (quick win)
2. Second: Expand `BlockParser` to find image blocks in divs/svgs
3. Third: Implement `parseBlockHTML()` with inline formatting
4. Fourth: Add NSTextAttachment support for inline images

## Testing

1. Hitchhiker's Guide - cover image displays
2. Books with `<b>`, `<i>`, `<em>` - formatting preserved
3. Books with inline images - images appear in text flow
4. Performance - ensure parsing isn't significantly slower
5. Existing functionality - block IDs, position tracking still work

## Future Extensions

This architecture makes it easy to add:
- `<table>` rendering
- `<code>` with syntax highlighting
- Custom CSS class → style mappings
- `<sup>`, `<sub>` for footnotes
- `<ruby>` for annotations (common in Asian language books)

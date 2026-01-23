# Cook - EPUB Rendering Improvement Loop

Automatically compare, analyze, fix, and verify EPUB rendering against the reference implementation.

## Arguments
- `$ARGUMENTS` - Required: `<book> <chapter>` (e.g., `frankenstein 1`)

## Workflow

### 1. Capture Comparison

Start the reference server if needed and capture all screenshots:

```bash
# Ensure reference server is running
curl -s http://localhost:3000/health || (cd ../reference-server && ./scripts/run &; sleep 5)

# Create output directory
mkdir -p /tmp/reader-tests

# Get dark-mode reference screenshot (768x1024 points = iPad Pro 11" at 2x Retina, fontSize=32 to match iOS)
REF_RESPONSE=$(curl -s "http://localhost:3000/screenshot?book=<book>&chapter=<chapter>&width=768&height=1024&theme=dark&fontSize=32&force=true")
REF_PATH=$(echo "$REF_RESPONSE" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)
cp "$REF_PATH" /tmp/reader-tests/ref_<book>_ch<chapter>.png

# Capture iOS screenshots (both renderers)
./scripts/run --screenshot --book=<book> --chapter=<chapter> --output=/tmp/reader-tests/ios_html_<book>_ch<chapter>.png
./scripts/run --screenshot --book=<book> --chapter=<chapter> --renderer=native --output=/tmp/reader-tests/ios_native_<book>_ch<chapter>.png

# Compose labeled comparison
uv run --with pillow scripts/compose-comparison.py <book> <chapter>
```

### 2. Display and Analyze

Use the Read tool to display `/tmp/reader-tests/comparison_<book>_ch<chapter>.png`

Analyze differences between the three views:
- **Reference (EPUB.js)** - The ground truth
- **iOS HTML (WebView)** - Should closely match reference
- **iOS Native** - May differ more, focus on critical issues

Look for discrepancies in:
| Aspect | What to Check |
|--------|---------------|
| Margins | Horizontal spacing from edges |
| Typography | Font family, size, weight, line-height |
| Alignment | Centered vs left-aligned titles/text |
| Spacing | Paragraph gaps, section breaks |
| Decorations | Horizontal rules, borders, dividers |
| Content | Missing text, truncation, overflow |
| Theme colors | Background and text match reference theme |

**Theme Colors (from reference):**
| Theme | Background | Text |
|-------|------------|------|
| `light` | #ffffff | #000000 |
| `dark` | #1a1a1a | #e0e0e0 |
| `sepia` | #f4ecd8 | #5b4636 |

### 3. Identify Root Cause

For each issue found, locate the responsible code:

| Issue Type | Primary File |
|------------|--------------|
| CSS/Styling | `Packages/ReaderKit/Sources/ReaderCore/CSSManager.swift` |
| WebView rendering | `Packages/ReaderKit/Sources/ReaderUI/WebPageViewController.swift` |
| Native rendering | `Packages/ReaderKit/Sources/ReaderUI/NativePageViewController.swift` |
| Margins/Preferences | `Packages/ReaderKit/Sources/ReaderCore/ReaderPreferences.swift` |
| HTML processing | `Packages/ReaderKit/Sources/ReaderCore/EPUBLoader.swift` |

### 4. Fix the Issue

Make targeted fixes. Keep changes minimal and focused. Common fixes:

**Margin issues:**
```swift
// In ReaderPreferences.swift
return stored > 0 ? CGFloat(stored) : 80 // Adjust default
```

**CSS styling issues:**
```swift
// In CSSManager.swift - add or modify CSS rules
h1 { text-align: center; }
hr { border: 1px solid #666; margin: 2em 0; }
```

**Typography issues:**
```swift
// In CSSManager.swift
body { font-family: Georgia, serif; line-height: 1.6; }
```

### 5. Verify Fix

After making changes:
1. Rebuild: `./scripts/build`
2. Re-run comparison: repeat from step 1
3. Display new comparison image
4. Confirm the issue is resolved

### 6. Iterate

Repeat steps 2-5 until the iOS rendering acceptably matches the reference.

Priority order:
1. **Content issues** - Missing or incorrect text (critical)
2. **Layout issues** - Margins, alignment, spacing (major)
3. **Typography issues** - Fonts, sizes, line-height (major)
4. **Decorative issues** - Rules, borders, styling (minor)

### 7. Report Results

When done, summarize:
- Issues found and fixed
- Remaining minor differences (if acceptable)
- Any issues that need deeper investigation

## Available Books

- `frankenstein` - Good for testing: has title pages, chapters, varied formatting
- `meditations` - Simpler formatting, good baseline test
- `the-metamorphosis` - Different styling, tests generalization
- `seven-pillars` - Seven Pillars of Wisdom, longer book for stress testing

## Reference Server API

### Get Spine Info

```bash
# Get chapter list with CFI data
curl -s "http://localhost:3000/books/<book>/info"
```

Returns spine array with `index`, `href`, `label`, `idref`, and `baseCfi` for each chapter.

### Screenshot Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `book` | Yes | Book slug |
| `chapter` | One of chapter/cfi | 0-based spine index |
| `cfi` | One of chapter/cfi | EPUB CFI (URL-encoded) |
| `width` | No | Viewport width (default: 1024) |
| `height` | No | Viewport height (default: 768) |
| `theme` | No | `light` (default), `dark`, or `sepia` |
| `fontSize` | No | Font size in pixels (default: browser default, use 32 to match iOS) |
| `format` | No | `path` (default) or `base64` |
| `force` | No | `true` to regenerate cached screenshot |

### CFI-Based Screenshots

For precise location testing, use CFI instead of chapter index:

```bash
# Get CFI from spine info
CFI=$(curl -s "http://localhost:3000/books/frankenstein/info" | jq -r '.spine[5].baseCfi')

# Request screenshot by CFI
curl -G "http://localhost:3000/screenshot" \
  --data-urlencode "book=frankenstein" \
  --data-urlencode "cfi=$CFI" \
  --data "width=834&height=1194&theme=dark"
```

## Tips

- Chapter 0 is often cover/boilerplate - start with chapter 1+
- Test the same fix across multiple books
- HTML renderer is primary focus (should match reference closely)
- Native renderer may have intentional differences
- After fixing, consider adding a deterministic UI test to prevent regression
- Use `/books/<book>/info` to discover spine structure and CFI values

## Example

```
/cook frankenstein 5

[Captures screenshots, displays comparison]

Issues found:
1. Chapter title not centered (reference is centered)
2. Missing horizontal rule after title

Fixing #1: Adding text-align: center to h1 in CSSManager.swift...
Fixing #2: Adding hr styling support...

[Rebuilds, recaptures, displays new comparison]

✓ Title now centered
✓ Horizontal rule now visible

Remaining: Minor line-height difference (acceptable)
```

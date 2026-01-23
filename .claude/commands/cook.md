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

# Get dark-mode reference screenshot (834x1194 = iPad)
REF_RESPONSE=$(curl -s "http://localhost:3000/screenshot?book=<book>&chapter=<chapter>&width=834&height=1194&theme=dark&force=true")
REF_PATH=$(echo "$REF_RESPONSE" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)
cp "$REF_PATH" /tmp/reader-tests/ref_<book>_ch<chapter>.png

# Capture iOS screenshots (both renderers)
BOOK=<book> CHAPTER=<chapter> ./scripts/test ui:testCaptureBothRenderers

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

## Tips

- Chapter 0 is often cover/boilerplate - start with chapter 1+
- Test the same fix across multiple books
- HTML renderer is primary focus (should match reference closely)
- Native renderer may have intentional differences
- After fixing, consider adding a deterministic UI test to prevent regression

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

# Cook - EPUB Rendering Improvement Loop

Iteratively debug and fix EPUB rendering issues using visual comparison.

## Arguments
- `$ARGUMENTS` - Required: `<book_keyword> <cfi>` (e.g., `Crash epubcfi(/6/22!)`)

## Workflow

### 1. Capture Screenshot

```bash
BOOK_KEYWORD="<book_keyword>" BOOK_CFI="<cfi>" ./scripts/test ui:testVisualDebugBookAtLocation
```

Screenshot saved to `/tmp/reader-tests/debug-<keyword>-cfi-<hash>-<timestamp>.png`

### 2. Display and Analyze

Use the Read tool to display the screenshot.

Look for rendering issues:
| Aspect | What to Check |
|--------|---------------|
| Layout | Content width, margins, column alignment |
| Typography | Font rendering, line-height, text wrapping |
| Spacing | Paragraph gaps, section breaks |
| Content | Missing text, truncation, overflow |

### 3. Identify Root Cause

| Issue Type | Primary File |
|------------|--------------|
| CSS/Styling | `Packages/ReaderKit/Sources/ReaderCore/CSSManager.swift` |
| HTML processing | `Packages/ReaderKit/Sources/ReaderUI/WebPageViewController.swift` |
| Margins/Layout | `Packages/ReaderKit/Sources/ReaderCore/ReaderPreferences.swift` |
| EPUB parsing | `Packages/ReaderKit/Sources/ReaderCore/EPUBLoader.swift` |

### 4. Fix the Issue

Make targeted, minimal fixes.

### 5. Verify Fix

1. Rebuild: `./scripts/build`
2. Re-run screenshot capture (step 1)
3. Display new screenshot
4. Confirm issue is resolved

### 6. Iterate

Repeat until rendering is correct.

## CFI Reference

CFI format: `epubcfi(/6/N!)` where N = (spine_index + 1) * 2

| Spine Index | CFI |
|-------------|-----|
| 0 | epubcfi(/6/2!) |
| 5 | epubcfi(/6/12!) |
| 10 | epubcfi(/6/22!) |

## Example

```
/cook Crash epubcfi(/6/22!)

[Captures screenshot, displays it]

Issue found: Text rendering in narrow column

Root cause: XHTML self-closing <div/> tags not properly closed for HTML5

Fix: Add fixXHTMLSelfClosingTags() in WebPageViewController.swift

[Rebuilds, recaptures, displays new screenshot]

✓ Text now renders at full width
```

# Visual Debug Test

Captures screenshots of any book at any CFI location for debugging rendering issues.

## Usage

```bash
BOOK_KEYWORD="<search-term>" BOOK_CFI="<cfi>" ./scripts/test ui:testVisualDebugBookAtLocation
```

## Parameters

- **BOOK_KEYWORD** (required): Text to match in book title (e.g., "Crash", "Frankenstein")
- **BOOK_CFI** (required): EPUB CFI to navigate to (e.g., "epubcfi(/6/22!)")
- **BOOK_PAGE_OFFSET** (optional): Pages to swipe forward after loading (e.g., "5")

## CFI Format

CFI format: `epubcfi(/6/N!)` where N = (spine_index + 1) * 2

| Spine Index | CFI |
|-------------|-----|
| 0 | epubcfi(/6/2!) |
| 5 | epubcfi(/6/12!) |
| 10 | epubcfi(/6/22!) |
| 15 | epubcfi(/6/32!) |

## Examples

```bash
# Open Crash book at spine index 10 (chapter 11)
BOOK_KEYWORD="Crash" BOOK_CFI="epubcfi(/6/22!)" ./scripts/test ui:testVisualDebugBookAtLocation

# Open Frankenstein at spine index 4
BOOK_KEYWORD="Frankenstein" BOOK_CFI="epubcfi(/6/10!)" ./scripts/test ui:testVisualDebugBookAtLocation

# Open and swipe forward 3 pages
BOOK_KEYWORD="Crash" BOOK_CFI="epubcfi(/6/22!)" BOOK_PAGE_OFFSET=3 ./scripts/test ui:testVisualDebugBookAtLocation
```

## Output

- Screenshot saved to: `/tmp/reader-tests/debug-<keyword>-cfi-<hash>-<timestamp>.png`
- Test output shows current position: "Page X of Y · Ch. A of B"

## Requirements

- Set `TEST_BOOKS_DIR` in `.env` to load external test books
- Books must be in the library (run `./scripts/run` first if needed)

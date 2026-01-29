# Plan: Native Renderer - Position Persistence

## Status: COMPLETED

Position persistence for native renderer is now implemented and tested, including mid-chapter position.

## Implementation Summary

**CFI position reporting** - `NativePageViewController.swift`:
- Added `updateCFIPosition()` method that generates CFI from current page position
- Uses `pageSpineIndices` to get spine index for current page
- Uses cached layout `PageOffset.firstBlockCharOffset` for sub-page precision
- Calls `onCFIPositionChanged?(cfi, spineIndex)` on every page change
- Called from `reportPositionChange()` which fires on scroll/navigation

**Position restoration** - `NativePageViewController.swift`:
- Added `initialCFI` parameter to init (matching WebPageViewController)
- Added `restorePositionFromCFI()` method that:
  1. Parses CFI to get spine index and character offset
  2. Finds all pages in target spine item
  3. Uses character offset to find the best matching page (not just first page)
- Called after pages are built in `buildPages()`

**Wiring** - `ReaderViewController.swift`:
- Updated both NativePageViewController creation sites to pass `initialCFI`
- Initial creation: `viewModel.initialCFI`
- Renderer switch: `viewModel.currentCFI`

## Test Results

```
# Chapter-level persistence
RENDERER=native ./scripts/test ui:testPositionPersistence
# Output: "Position persistence verified! Saved at Ch.6, restored to Ch.6"
# TEST SUCCEEDED

# Mid-chapter persistence (new test)
RENDERER=native ./scripts/test ui:testMidChapterPositionPersistence
# Output: "Saved: Page 3 of 6 · Ch. 8, Restored: Page 3 of 6 · Ch. 8"
# TEST SUCCEEDED
```

## Files Modified

| File | Change |
|------|--------|
| `NativePageViewController.swift` | Added `updateCFIPosition()`, `restorePositionFromCFI()` with character offset matching, `initialCFI` parameter |
| `ReaderViewController.swift` | Pass `initialCFI` when creating native renderer |
| `PositionPersistenceTests.swift` | Added `testMidChapterPositionPersistence` test |

## Key Insight

The new `testMidChapterPositionPersistence` test exposed that the HTML renderer also fails mid-chapter restoration (resets to page 1 of chapter). This is a separate issue not addressed in this PR - the native renderer now correctly persists and restores mid-chapter positions.

## Verification

Position persistence now works for native renderer:
1. Open book, navigate to chapter 6, slide to middle of chapter
2. Kill app completely
3. Reopen app
4. Book opens to the same page within the chapter (not page 1)

The CFI format used: `epubcfi(/6/N[spineItemId]!:charOffset)`

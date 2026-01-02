# iPadOS TextKit 1 Reader MVP Plan

## MVP goal

A reflowable, paged reader on iPadOS using TextKit 1 with solid text selection and a custom action flow: **Send to LLM → modal Q&A → dismiss → return to same spot**.

## Scope decisions (MVP)

* Content format: **EPUB → `NSAttributedString`** (basic loader, full spine; later pages blank).
* Paging: **horizontal page-by-page swipe** (DONE).
* Selection: **system selection handles**; custom action via the system edit menu (DONE).
* Persistence: restore **reading position within the current chapter** (page index + character offset) (DONE).

## Deliverables

* Reader screen (paged) (DONE)
* Selection → “Send to LLM” action (DONE)
* LLM modal (answer + follow-up question box + history) (DONE)
* Basic settings (font size) (DONE)
* Position restore on rotate + font change (best-effort) (DONE)

---

## Architecture

### Modules

* `ReaderCore` (pure Swift):

  * Chapter model (`id`, `attributedText`, optional `title`)
  * Pagination cache
  * Selection extraction utilities
  * Position model (chapterId, pageIndex, characterOffset)
* `ReaderUI` (UIKit):

  * ReaderViewController (UIPageViewController for paging)
  * PageViewController (wraps UITextView per page)
  * Selection + action UI integration

### Key objects

* TextKit 1 (isolated text systems):

  * Each page has its own `NSTextStorage` (substring of page range)
  * Each page has its own `NSLayoutManager`
  * Each page has its own `NSTextContainer`
* UI:

  * `UIPageViewController` for horizontal paging
  * `PageViewController` per page wrapping `UITextView`
  * Each `UITextView` uses its page's isolated text system

---

## Build steps

### 0) Infrastructure (one-command workflows)

* Ensure scripts exist and are the only entry points:

  * `./scripts/bootstrap` generates the Xcode project via XcodeGen and installs/pins tools (DONE)
  * `./scripts/build` uses `xcodebuild` with a hardcoded scheme, configuration, and simulator destination (DONE)
  * `./scripts/test` runs unit tests with the same hardcoded destination (DONE)
  * `./scripts/lint` runs pinned SwiftLint/SwiftFormat versions (DONE)
* Commit `Package.resolved` (DONE).

### 1) Skeleton app

* Create SPM packages (DONE):

  * `ReaderCore` (DONE)
  * `ReaderUI` (DONE)
* SwiftUI app with `ReaderView(chapter:)` as root; keep the Xcode app target thin (DONE).
* Hardcode a sample chapter (lorem + headings + italics) (DONE).

### 2) Text engine + paging (TextKit 1) (DONE)

* Create `TextEngine` owning (DONE):

  * `NSTextStorage` populated from chapter attributed string
  * single `NSLayoutManager`
* Implement `paginate(pageSize:insets:fontScale:) -> [Page]` (DONE):

  * Create containers sequentially for the given page rect
  * Associate each container with a `Page(id, containerIndex, range)`
  * Stop when laid-out range reaches end of text
* Cache pages keyed by `(chapterId, pageSize, insets, fontScale)` (DONE).
* Define deterministic position mapping (DONE):

  * Store reading position as `CharacterOffset` (global index in chapter string)
  * Derive `pageIndex` by finding the first page whose `range` contains or follows the offset
* Tests (DONE):

  * `TextEngineTests` validate pagination ranges are contiguous, non-overlapping, and cover the full chapter
  * `TextEngineTests` validate `CharacterOffset` → `pageIndex` mapping

### 3) Page render (MVP: UITextView) (DONE)

* `PageTextView` (UIViewRepresentable) that constructs a `UITextView` (DONE):

  * Assign the shared `NSLayoutManager` + its `NSTextStorage`
  * Assign the page’s `NSTextContainer`
  * Disable scrolling, set transparent background, set padding to 0 (container already represents inset)
* Only render a small window of pages around the current page (e.g., current ±2) and release views outside that window deterministically (DONE).
* Tests:

  * Snapshot tests for `PageTextView` (typography + insets + selection affordances) (DONE)

### 4) Pager UI (DONE)

* `TabView(selection:)` with `.page` style (DONE).
* Maintain `@State currentPageIndex` (DONE).
* On appear: jump to restored page index (DONE).

### 5) Selection → Send to LLM (DONE)

* Capture selected text (DONE):

  * For each visible page `UITextView`, attach `UIEditMenuInteraction` (or custom UIMenu actions) so “Send to LLM” appears in the system edit menu.
  * When invoked, resolve selection range from the `UITextView` and convert it to the chapter-global range.
* Action (DONE):
  * Extract selected string + context window (e.g., ±500 chars or enclosing paragraph if available)
  * Open `LLMModal(payload)`.
* Tests:
  * Minimal UI tests for selection → “Send to LLM” appearing in the edit menu (deferred)

### 6) LLM modal (DONE)

* SwiftUI sheet with (DONE):

  * Answer view (streaming later; for MVP, one-shot)
  * Follow-up input + send (not yet for mvp, but design for it)
  * Dismiss returns to reader (no position loss)
* Tests:
  * UI test for modal present/dismiss preserving position (deferred)

### 7) Settings + reflow (DONE)

* Settings sheet: font size (slider) (DONE).
* On change (DONE):

  * Invalidate pagination cache
  * Re-paginate for current geometry
  * Restore position using character offset → page index mapping

### 8) Rotation + layout changes (DONE)

* Detect size class / geometry changes (DONE).
* Debounce repagination (e.g., 150–300ms) (DONE).
* Preserve reading position via stored `characterOffset` (DONE).

---

## Definition of done (MVP)

* Swipe pages smoothly on iPad (DONE).
* Text reflows when font size changes (DONE).
* User can select text reliably (DONE).
* “Send to LLM” appears reliably in the system edit menu when selection exists (DONE).
* `Package.resolved` committed.

---

## Risks / likely potholes

* ~~Shared TextKit 1 objects caused blank pages: container 0 consumed all text, pages 1+ were blank.~~ (FIXED)
* **Solution**: Isolated text systems architecture - each page gets its own NSTextStorage (substring), NSLayoutManager, and NSTextContainer. No sharing = no interference.
* **Architecture choice**: UIKit (UIPageViewController) over SwiftUI (TabView) for precise layout control and proper margins.

---

## Tests (MVP)

* Unit tests for pagination (DONE):
  * page ranges are contiguous, non-overlapping, and cover the chapter
  * last page range reaches end of text
* Unit tests for position mapping (DONE):
  * given a `CharacterOffset`, mapping returns the expected page index
  * text container actual ranges are non-empty (DONE)

---

## Next after MVP

* Multi-chapter navigation + TOC
* Modal Q&A works; dismiss returns to exact spot.
* Search
* Highlight persistence (if desired)
* Robust EPUB ingestion (HTML/CSS strategy)
* Custom renderer (replace `UITextView` pages for performance/control)

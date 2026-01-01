# iPadOS TextKit 2 Reader MVP Plan

## MVP goal

A reflowable, paged reader on iPadOS using TextKit 2 with solid text selection and a custom action flow: **Send to LLM → modal Q&A → dismiss → return to same spot**.

## Scope decisions (MVP)

* Content format: **single chapter as `NSAttributedString`** (stub loader). No EPUB/HTML/CSS yet.
* Paging: **horizontal page-by-page swipe**.
* Selection: **system selection handles**; custom action surfaced via the system edit menu (no custom overlay).
* Persistence: restore **reading position within the current chapter** (page index + character offset). No cross-chapter anchors.

## Deliverables

* Reader screen (paged)
* Selection → “Send to LLM” action
* LLM modal (answer + follow-up question box + history)
* Basic settings (font size)
* Position restore on rotate + font change (best-effort)

---

## Architecture

### Modules

* `ReaderCore` (pure Swift):

  * Chapter model (`id`, `attributedText`, optional `title`)
  * Pagination cache
  * Selection extraction utilities
  * Position model (chapterId, pageIndex, characterOffset)
* `ReaderUI` (SwiftUI + UIKit bridges):

  * Pager UI
  * Page view hosting
  * Selection + action UI integration

### Key objects

* TextKit 2:

  * `NSTextContentManager`
  * `NSTextLayoutManager`
  * `NSTextContainer` (one per page)
* UI:

  * `TabView` with `.page` style (MVP)
  * Page view implemented as **`UITextView` per page** using a **shared `NSTextContentManager` + `NSTextLayoutManager`** and a **distinct `NSTextContainer` per page**

---

## Build steps

### 0) Infrastructure (one-command workflows)

* Ensure scripts exist and are the only entry points:

  * `./scripts/bootstrap` generates the Xcode project via XcodeGen and installs/pins tools (DONE)
  * `./scripts/build` uses `xcodebuild` with a hardcoded scheme, configuration, and simulator destination (DONE)
  * `./scripts/test` runs unit tests with the same hardcoded destination (DONE)
  * `./scripts/lint` runs pinned SwiftLint/SwiftFormat versions (DONE)
* Commit `Package.resolved` (pending; not generated yet).

### 1) Skeleton app

* Create SPM packages (DONE):

  * `ReaderCore` (DONE)
  * `ReaderUI` (DONE)
* SwiftUI app with `ReaderView(chapter:)` as root; keep the Xcode app target thin (DONE).
* Hardcode a sample chapter (lorem + headings + italics).

### 2) Text engine + pagination (TextKit 2)

* Create `TextEngine` owning:

  * `NSTextContentManager` populated from chapter attributed string
  * single `NSTextLayoutManager`
* Implement `paginate(pageSize:insets:fontScale:) -> [Page]`:

  * Create containers sequentially for the given page rect
  * Associate each container with a `Page(id, containerIndex, range)`
  * Stop when laid-out range reaches end of text
* Cache pages keyed by `(chapterId, pageSize, insets, fontScale)`.
* Define deterministic position mapping:

  * Store reading position as `CharacterOffset` (global index in chapter string)
  * Derive `pageIndex` by finding the first page whose `range` contains or follows the offset
* Tests:

  * `TextEngineTests` validate pagination ranges are contiguous, non-overlapping, and cover the full chapter
  * `TextEngineTests` validate `CharacterOffset` → `pageIndex` mapping

### 3) Page rendering (MVP: UITextView)

* `PageTextView` (UIViewRepresentable) that constructs a `UITextView`:

  * Assign the shared `NSTextLayoutManager` + its `NSTextContentManager`
  * Assign the page’s `NSTextContainer`
  * Disable scrolling, set transparent background, set padding to 0 (container already represents inset)
* Only render a small window of pages around the current page (e.g., current ±2) and release views outside that window deterministically.
* Tests:

  * Snapshot tests for `PageTextView` (typography + insets + selection affordances)

### 4) Pager UI

* `TabView(selection:)` with `.page` style.
* Maintain `@State currentPageIndex`.
* On appear: jump to restored page index.

### 5) Selection → Send to LLM

* Capture selected text:

  * For each visible page `UITextView`, attach `UIEditMenuInteraction` (or custom UIMenu actions) so “Send to LLM” appears in the system edit menu.
  * When invoked, resolve selection range from the `UITextView` and convert it to the chapter-global range.
* Action:
  * Extract selected string + context window (e.g., ±500 chars or enclosing paragraph if available)
  * Open `LLMModal(payload)`.
* Tests:
  * Minimal UI tests for selection → “Send to LLM” appearing in the edit menu

### 6) LLM modal

* SwiftUI sheet with:

  * Answer view (streaming later; for MVP, one-shot)
  * Follow-up input + send (not yet for mvp, but design for it)
  * Dismiss returns to reader (no position loss)
* Tests:
  * UI test for modal present/dismiss preserving position

### 7) Settings + reflow

* Settings sheet: font size (slider).
* On change:

  * Invalidate pagination cache
  * Re-paginate for current geometry
  * Restore position using character offset → page index mapping

### 8) Rotation + layout changes

* Detect size class / geometry changes.
* Debounce repagination (e.g., 150–300ms).
* Preserve reading position via stored `characterOffset`.

---

## Definition of done (MVP)

* Swipe pages smoothly on iPad.
* Text reflows when font size changes.
* User can select text reliably.
* “Send to LLM” appears reliably in the system edit menu when selection exists.
* `Package.resolved` committed.

---

## Risks / likely potholes

* `UITextView` + shared TextKit 2 objects across many pages: manage memory by limiting instantiated pages.
* Repagination jank: cache + lazy paginate.

---

## Tests (MVP)

* Unit tests for pagination:
  * page ranges are contiguous, non-overlapping, and cover the chapter
  * last page range reaches end of text
* Unit tests for position mapping:
  * given a `CharacterOffset`, mapping returns the expected page index
  * mapping remains stable across font size changes (best-effort)

---

## Next after MVP

* Multi-chapter navigation + TOC
* Modal Q&A works; dismiss returns to exact spot.
* Search
* Highlight persistence (if desired)
* EPUB ingestion (HTML/CSS strategy)
* Custom renderer (replace `UITextView` pages for performance/control)

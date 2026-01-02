# iPadOS TextKit 1 Reader

## MVP Goal

A reflowable, paged reader on iPadOS using TextKit 1 with solid text selection and a custom action flow: **Send to LLM → modal Q&A → dismiss → return to same spot**.

## Current Status

MVP complete! The app can:
- Load EPUB files and display full spine
- Paginate horizontally with swipe gestures
- Handle text selection with "Send to LLM" action
- Show LLM modal for Q&A
- Persist reading position across rotations and font changes
- Adjust font size via settings

---

## Architecture

### Modules

- **ReaderCore** (pure Swift, no UI dependencies):
  - Chapter model (`id`, `attributedText`, optional `title`)
  - TextEngine with pagination cache
  - Selection extraction utilities
  - Position model (chapterId, pageIndex, characterOffset)

- **ReaderUI** (UIKit + SwiftUI):
  - ReaderViewController (UIPageViewController for paging)
  - PageViewController (wraps UITextView per page)
  - Selection + action UI integration
  - Settings and LLM modal views

### Key Architecture Decision: Isolated Text Systems

Each page has its own complete TextKit stack:
- Own `NSTextStorage` (substring of page's character range)
- Own `NSLayoutManager`
- Own `NSTextContainer`

**Why**: Shared TextKit objects caused blank pages - container 0 would consume all text, leaving pages 1+ empty. Isolated systems eliminate interference between pages.

### UI Architecture

- **UIPageViewController** for horizontal paging (chosen over SwiftUI TabView for precise layout control)
- **PageViewController** per page wrapping **UITextView**
- Each UITextView uses its page's isolated text system

### Position Persistence

- Character offset as source of truth (not page index)
- Maps character offset → page index during layout changes
- Ensures consistent position restoration across font changes and rotations

---

## Next Steps

Potential future enhancements (not committed to timeline):

- Multi-chapter navigation + table of contents
- Search functionality
- Highlight persistence
- More robust EPUB ingestion (advanced HTML/CSS handling)
- Custom page renderer (replace UITextView for performance/control)
- Book library management

# iPadOS EPUB Reader

## MVP Goal

A reflowable, paged EPUB reader on iPadOS with library management and planned text selection for LLM integration.

## Current Status

**Working:**
- ✅ Library view with book list
- ✅ Document picker for importing EPUBs
- ✅ Book storage in Application Support with metadata in UserDefaults
- ✅ WKWebView-based HTML rendering with CSS pagination
- ✅ Horizontal page swiping via JavaScript
- ✅ Font scale adjustment (1.25x - 2.0x)
- ✅ Text justification toggle
- ✅ Reading position persistence across launches

**In Progress/Planned:**
- 🔄 Text selection + "Send to LLM" action (WKWebView-based)
- 📋 Table of contents / chapter navigation
- 📋 Search within book
- 📋 Better EPUB support (complex CSS, fonts, embedded media)

---

## Architecture

### Modules

- **ReaderCore** (pure Swift):
  - `EPUBLoader`: Extracts HTML sections from EPUB using ZIPFoundation
  - `HTMLSection`: Represents chapter content as HTML string
  - `Book`: Model for library entries (id, title, filePath, dates)
  - `BookLibraryService`: Manages import, storage, metadata
  - File-based debug logging for device debugging

- **ReaderUI** (UIKit + SwiftUI):
  - `LibraryView`: SwiftUI grid of books with document picker
  - `ReaderViewController`: Main reader container
  - `WebPageViewController`: WKWebView with JS-based pagination
  - `ReaderContainerView`: SwiftUI wrapper connecting library → reader
  - Settings for font scale and text justification

### Key Architecture Decision: WKWebView + CSS Pagination

**Why WKWebView over TextKit:**
- Better HTML/CSS support for EPUB content
- CSS pagination (`column-width`, `column-gap`) handles reflowing
- JavaScript for page navigation and selection handling
- Simpler than managing complex TextKit layout stacks

**Trade-off:** Text selection integration requires JavaScript bridge (vs native UITextView selection)

### UI Architecture

- **LibraryView** (SwiftUI) shows all books
- **DocumentPicker** (UIDocumentPickerViewController) for importing
  - Files copied to `tmp/Inbox` (already in sandbox, no security-scoped access needed)
- **ReaderViewController** hosts **WebPageViewController**
- **WebPageViewController** contains single **WKWebView** with all HTML sections
  - CSS columns create pages
  - JavaScript handles page turn gestures and reports page numbers
  - Font scale applied via CSS transform

### Book Storage

- Books stored in `Application Support/Books/{UUID}/book.epub`
- Metadata (title, dates, file path) in UserDefaults as JSON
- Import uses `NSFileCoordinator` for safe file copying
- Security-scoped resource access only for files outside sandbox

### Position Persistence

- Currently: Auto-opens last read book on launch
- TODO: Persist page/scroll position within books

---

## Next Steps

### Immediate Priorities

1. **Text Selection + LLM Integration**
   - Implement JavaScript-based text selection in WKWebView
   - Add "Send to LLM" action via message handler
   - Create modal Q&A interface
   - Return to same position after modal dismissal

2. **Table of Contents**
   - Extract TOC from EPUB spine/navigation
   - Chapter list view with jump-to-chapter
   - Current chapter indicator

3. **Search Within Book**
   - JavaScript-based text search across all HTML sections
   - Results list with context snippets
   - Jump to search result with highlighting

### Future Enhancements

- Better EPUB support: complex CSS, custom fonts, embedded media, images
- Highlight and annotation persistence
- Book metadata editing (title, author)
- Export highlights/notes
- Pagination position persistence within books
- iCloud sync for library and reading positions

### Cleanup Tasks

- Remove old TextKit/PageViewController code (unused)
- Fix warnings: LSSupportsOpeningDocumentsInPlace, orientation support, launch storyboard

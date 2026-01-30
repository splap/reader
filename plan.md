# Plan: Adopt EPUB.js Pagination Approach (Avoid TOC Table Text Shrink)

## Goal
Match the pagination behavior of EPUB.js (reference server) to prevent WebKit from rendering table-based TOC text smaller than paragraph text, without relying on brittle CSS overrides.

## Key Observations from EPUB.js
- **Explicit px sizing**: EPUB.js sets fixed `width`/`height` (px) on the content element and updates the **meta viewport** to those exact dimensions (scale=1.0, non‑scalable).
- **JS-driven columns**: It sets `column-width`, `column-gap`, and `column-fill` on the **body** using explicit px values computed from the content width (not `100vw` or CSS `calc(...)`).
- **Margins are external**: Viewer container is resized so the content width already accounts for margins; EPUB.js does not use body padding for margins when paginating.
- **WebKit layout hints**: It applies `overflow-y: hidden`, `margin: 0`, `box-sizing: border-box`, `max-width: inherit`, and `-webkit-line-box-contain: block glyphs replaced` for pagination consistency.

## Proposed Approach (High-Level)
1. **Move margins outside the content**
   - Instead of padding the body, shrink the WebView's visible layout area by the margin size (like EPUB.js' viewer container sizing). The HTML content should be laid out in a "margin-free" viewport.

2. **Use explicit px sizing for the content**
   - Set fixed `width` and `height` in px on the content element (body) based on the actual viewport size minus margins.
   - Update the document's `<meta name="viewport">` to the exact `width` and `height` so WebKit doesn't run autosizing heuristics.

3. **Replace CSS `100vw`/`calc()` columns with JS-set px columns**
   - Compute `column-width` and `column-gap` in Swift/JS and set them on the content element using explicit px values.
   - Avoid `100vw` to prevent WebKit interpreting widths differently per element (tables vs paragraphs).

4. **Mirror EPUB.js' pagination CSS knobs**
   - Apply the same pagination-oriented CSS properties to the body:
     - `overflow-y: hidden`
     - `margin: 0`
     - `box-sizing: border-box`
     - `max-width: inherit`
     - `column-fill: auto`
     - `-webkit-line-box-contain: block glyphs replaced`

5. **Treat font size as a content parameter, not a viewport parameter**
   - Keep font size on body as today, but ensure content sizing is always recalculated (width/height/columns + viewport meta) after any font size or margin change.

## Implementation Steps (Concrete)
1. **Layout contract**
   - Define a single "content width/height" that is `viewport - (margin * 2)`.
   - Store that value as the authoritative width/height for pagination.

2. **HTML injection changes**
   - In the HTML wrapper, remove body padding for margins.
   - Inject a function that:
     - sets `<meta name="viewport" content="width=..., height=..., initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no">`
     - sets `body.style.width/height` in px
     - sets `column-width`/`column-gap` on body in px
     - applies EPUB.js-style layout CSS

3. **WebView container sizing**
   - Adjust the WebView's effective layout area (or an inner container div) to the content size by applying margins outside the content area (like the reference server's `#viewer` sizing).

4. **Re-layout triggers**
   - On font size change, margin change, or device rotation:
     - recompute content width/height
     - update viewport meta
     - reapply body width/height and column CSS
     - re-measure column width for pagination logic

5. **Verification plan**
   - Compare Frankenstein CONTENTS vs Letter 2 with the same font scale/margins. Confirm visual sizes match.
   - Repeat with other EPUBs that use tables or narrow content blocks.
   - Confirm pagination and CFI position restore remain stable.

## Risks / Open Questions
- **WebView sizing**: need a reliable way to reduce the effective layout width without relying on body padding (may require a container wrapper or layout constraints).
- **Viewport updates**: updating meta viewport in a WKWebView must be done before layout for each spine item; ensure timing aligns with spine loading.
- **Pagination math**: existing column-width queries and page snapping logic must align with the new content width/height.

## Next Step
If you want, I can draft the concrete code changes in Swift/JS once you approve this plan.

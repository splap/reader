# Visual Comparison Testing

Compare EPUB rendering between the reference server (EPUB.js) and the iOS app's HTML and Native renderers.

## Arguments
- `$ARGUMENTS` - Optional: `<book> <chapter>` (defaults to `frankenstein 0`)

## Workflow

1. Parse arguments: Extract book slug and chapter number from `$ARGUMENTS`, defaulting to `frankenstein 0`

2. Capture reference screenshot from EPUB.js server:
   ```bash
   # Check if server is running, start if needed
   curl -s http://localhost:3000/health || (cd ../reference-server && ./scripts/run &; sleep 5)

   # Get reference screenshot (834x1194 = iPad dimensions, dark mode)
   curl -s "http://localhost:3000/screenshot?book=<book>&chapter=<chapter>&width=834&height=1194&theme=dark"
   # Copy to /tmp/reader-tests/ref_<book>_ch<chapter>.png
   ```

3. Capture iOS screenshots (both renderers):
   ```bash
   BOOK=<book> CHAPTER=<chapter> ./scripts/test ui:testCaptureBothRenderers
   ```
   This saves:
   - `/tmp/reader-tests/ios_<book>_ch<chapter>_html.png` (WebView renderer)
   - `/tmp/reader-tests/ios_<book>_ch<chapter>_native.png` (Native renderer)

4. Compose labeled comparison image:
   ```bash
   uv run --with pillow scripts/compose-comparison.py <book> <chapter>
   ```
   Output: `/tmp/reader-tests/comparison_<book>_ch<chapter>.png`

5. Display the comparison image to the user using the Read tool

6. Analyze the visual differences between:
   - Reference (EPUB.js) - the ground truth
   - iOS HTML (WebView) - our WebView-based renderer
   - iOS Native - our native UIKit renderer

7. Report findings:
   - Identify specific rendering differences
   - Prioritize issues by severity
   - Suggest fixes or deterministic tests

## Available Books
- `frankenstein` - Frankenstein by Mary Shelley
- `meditations` - Meditations by Marcus Aurelius
- `the-metamorphosis` - The Metamorphosis by Franz Kafka

## Output Files
| File | Description |
|------|-------------|
| `ref_<book>_ch<chapter>.png` | Reference from EPUB.js |
| `ios_<book>_ch<chapter>_html.png` | iOS WebView renderer |
| `ios_<book>_ch<chapter>_native.png` | iOS Native renderer |
| `comparison_<book>_ch<chapter>.png` | Labeled side-by-side image |

## Tips
- Run `open /tmp/reader-tests` to view all screenshots
- Chapter indices are 0-based (chapter 0 is the first spine item)
- Reference server must be running for reference screenshots
- The comparison image is the primary output - show it to the user

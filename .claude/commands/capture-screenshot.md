# Capture iOS Screenshot

Capture a screenshot from the iOS reader app for a specific book and chapter.

## Arguments
- `$ARGUMENTS` - Optional: `<book> <chapter>` (defaults to `frankenstein 0`)

## Steps

1. Parse arguments from `$ARGUMENTS`, defaulting to `frankenstein 0`

2. Run the UI test to capture screenshot:
   ```bash
   BOOK=<book> CHAPTER=<chapter> ./scripts/test ui:testCaptureForComparison
   ```

3. Verify screenshot was saved to `/tmp/reader-tests/ios_<book>_ch<chapter>.png`

4. Open the screenshot for viewing:
   ```bash
   open /tmp/reader-tests/ios_<book>_ch<chapter>.png
   ```

## Available Books
- `frankenstein` - Frankenstein by Mary Shelley
- `meditations` - Meditations by Marcus Aurelius
- `the-metamorphosis` - The Metamorphosis by Franz Kafka

## Notes
- Chapter indices are 0-based
- Screenshots are saved to `/tmp/reader-tests/`
- Use `/visual-compare` to compare against reference screenshots

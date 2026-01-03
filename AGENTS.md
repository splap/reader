Core principle

Make the project boring and deterministic.
If a human can build/test it with one command, agents will succeed. Otherwise, they will fail unpredictably.

when you've made a change, run the app yourself so i see the result.

## Simulator Management (CRITICAL)

**ONE SIMULATOR PER SESSION** - Each Claude Code session should use exactly ONE simulator instance for all operations.

### Session Start - Boot and Track Simulator

At the start of a coding session, boot the simulator ONCE and save its UDID:

```bash
# Boot the simulator (if not already booted)
xcrun simctl boot "iPad Pro 11-inch (M4)" 2>/dev/null || true

# Get and save the UDID to a session file
SIMULATOR_UDID=$(xcrun simctl list devices available | \
  grep "iPad Pro 11-inch (M4)" | \
  grep -v "unavailable" | \
  head -1 | \
  grep -o "[0-9A-F]\{8\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{12\}")

echo "$SIMULATOR_UDID" > /tmp/reader-simulator-session.txt
echo "Using simulator: $SIMULATOR_UDID"
```

### Throughout Session - Always Use Tracked Simulator

For ALL subsequent operations (loading books, running tests, installing app):

```bash
# Read the session simulator UDID
SIMULATOR_UDID=$(cat /tmp/reader-simulator-session.txt 2>/dev/null)

# Use it for operations
xcrun simctl get_app_container "$SIMULATOR_UDID" com.splap.reader data
```

### Why This Matters

- Running tests creates new app containers, so UDID stays same but container path changes
- Each test run may clear app state, so books need to be in the RIGHT container
- Multiple simulators = confusion about which one has books, which is running tests
- **NEVER** query for simulator UDID more than once per session unless explicitly needed

## Test Books Location

Test epub files are located at: `/Volumes/jimini/media/books`

To load test books into the SESSION simulator:
```bash
# Get session simulator
SIMULATOR_UDID=$(cat /tmp/reader-simulator-session.txt)

# Get current app container (may change between test runs)
APP_CONTAINER=$(xcrun simctl get_app_container "$SIMULATOR_UDID" com.splap.reader data)

# Load books
BOOKS_DIR="$APP_CONTAINER/Documents/TestBooks"
mkdir -p "$BOOKS_DIR"
cp /Volumes/jimini/media/books/*.epub "$BOOKS_DIR/"
```

Available test books include:
- Consider-Phlebas.epub (Banks, Ian M.)
- The-Optimist.epub
- ai_engineering_building_applications_with_foundation_models_chip_huyen.epub
- silent_sun_hard_science_fiction_brandon_q_morris_morris_brandon_q.epub
- the_fish_that_ate_the_whale_the_life_and_times_of_cohen_rich.epub
- the_persian_a_novel_david_mccloskey.epub
- the_ultimate_hitchhikers_guide_to_the_galaxy_five_novels_adams_douglas.epub

## Debugging and Reading Logs

### For Physical iPad (Primary)
Unified logging (os_log/Logger) doesn't reliably stream to Mac from iOS 26+ devices.

**Best approach:** Write debug logs to a file in the app, then pull it:

1. Add file logging in your code:
```swift
private let debugLogURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("import-debug.log")

private func writeDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logEntry = "[\(timestamp)] \(message)\n"
    if let data = logEntry.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: debugLogURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: debugLogURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try? fileHandle.close()
            }
        } else {
            try? data.write(to: debugLogURL)
        }
    }
}
```

2. Pull the log from device:
```bash
xcrun devicectl device copy from \
  --device <DEVICE_UDID> \
  --domain-type appDataContainer \
  --domain-identifier com.splap.reader \
  --source "Library/Application Support/import-debug.log" \
  --destination /tmp/debug.log

cat /tmp/debug.log
```

### For Simulator (Fallback)
```bash
xcrun simctl spawn booted log stream --style compact --debug --predicate 'subsystem == "com.splap.reader"'
```

**Note:** NSLog() and print() may not appear in device logs on newer iOS. Use file logging instead.

1. Project structure (most important)
    Prefer Swift Package Manager (SPM) for feature code.
    Keep the Xcode app target thin (wiring + assets only).
    If you need Xcode projects, generate them via Tuist or XcodeGen.
    Never rely on manual file adds or target membership.


2. One-command workflows (agents must only call scripts)
    use these scripts as much as possible
        ./scripts/bootstrap – install deps, generate project
        ./scripts/build – deterministic xcodebuild
        ./scripts/test – unit tests (UI tests optional/separate)
        ./scripts/lint – SwiftLint / SwiftFormat
        ./scripts/run – builds and runs the app

3. Headless, explicit builds
    Always use xcodebuild, never Xcode UI.
    Hard-code scheme, configuration, and simulator destination.
    Example destination: iPhone 15, iOS latest.
    This avoids simulator and scheme ambiguity.


6. Guardrails
    Add small, high-signal unit tests for all new logic.
    Snapshot tests for SwiftUI where regressions matter.
    Commit Package.resolved and pin formatter/linter versions.

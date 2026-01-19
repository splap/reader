Core principle

Make the project boring and deterministic.
If a human can build/test it with one command, agents will succeed. Otherwise, they will fail unpredictably.

when you've made a change, run the app yourself so i see the result.

## CRITICAL: Python via UV Only

**NEVER use `pip install`. Always use `uv` for Python.**

```bash
# WRONG - never do this
pip install transformers torch coremltools
python scripts/convert_bge_to_coreml.py

# CORRECT - always use uv
uv run --with transformers --with torch --with coremltools python scripts/convert_bge_to_coreml.py
```

`uv` handles virtual environments and dependencies automatically. No need to create venvs or install packages globally.

## CRITICAL: Default to iOS Simulator

**ALWAYS USE THE iOS 26 SIMULATOR BY DEFAULT** - Unless explicitly instructed otherwise, all development, testing, and debugging should happen on the iOS 26 simulator (iPad Pro 11-inch M4).

- Always use scripts/run script when you want to compile and run the code on the simulator. 
- Only use physical device when explicitly requested by the user
- The simulator is faster, more reliable, and easier to automate

## Simulator Management (CRITICAL)

**ONE SIMULATOR PER GIT WORKTREE** - We name our simulator sessions for their worktree and ensure a given worktree alwyas uses the same simulator
- if we are not in a git worktree, the worktree name is "none", use that to know wht simulator to use when not in git worktree

### Session Start - Use Running Simulator or Boot One

At the start of a coding session, check if simulator is already running. If so, use it. Only boot a new one if the one you expect to use isn't running.

```bash
# First, check if any simulator is already booted
SIMULATOR_UDID=$(xcrun simctl list devices | grep "(Booted)" | head -1 | \
  grep -o "[0-9A-F]\{8\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{12\}")

if [ -n "$SIMULATOR_UDID" ]; then
    echo "Using already-running simulator: $SIMULATOR_UDID"
else
    # No simulator running, boot the iOS 26 iPad
    xcrun simctl boot "iPad Pro 11-inch (M4)" 2>/dev/null || true
    SIMULATOR_UDID=$(xcrun simctl list devices | grep "(Booted)" | head -1 | \
      grep -o "[0-9A-F]\{8\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{12\}")
    echo "Booted new simulator: $SIMULATOR_UDID"
fi

echo "$SIMULATOR_UDID" > /tmp/reader-simulator-session.txt
```

**IMPORTANT**: Never boot a simulator if one is already running. This prevents duplicate simulators on different iOS versions.

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

Test epub files location: Set `TEST_BOOKS_DIR` environment variable to your epub directory

To load test books into the SESSION simulator:
```bash
# Get session simulator
SIMULATOR_UDID=$(cat /tmp/reader-simulator-session.txt)

# Get current app container (may change between test runs)
APP_CONTAINER=$(xcrun simctl get_app_container "$SIMULATOR_UDID" com.splap.reader data)

# Load books
BOOKS_DIR="$APP_CONTAINER/Documents/TestBooks"
mkdir -p "$BOOKS_DIR"
cp "$TEST_BOOKS_DIR"/*.epub "$BOOKS_DIR/"
```

**Bundled books** (included in app, appear on first launch):
- Frankenstein (Mary Shelley)
- Meditations (Marcus Aurelius)
- The Metamorphosis (Franz Kafka)

Additional test books can be loaded via `TEST_BOOKS_DIR` environment variable.

## CRITICAL: Deployment Verification

**Code is NOT deployed until you verify it's running.** A successful build does NOT mean the code is deployed.

### Required Verification Steps

1. **Add a temporary verification log** when adding new code paths:
```swift
Self.logger.warning("DEPLOY_VERIFY: MyNewFeature initialized")
```
Use `.warning` level - it always shows in logs. `.debug` and `.info` may be filtered.

2. **Build, install, and launch**:
```bash
./scripts/build
xcrun simctl install booted .build/DerivedData/Build/Products/Debug-iphonesimulator/ReaderApp.app
xcrun simctl terminate booted com.splap.reader 2>/dev/null || true
xcrun simctl launch booted com.splap.reader
```

3. **Verify the log appears**:
```bash
xcrun simctl spawn booted log show --style compact --debug --predicate 'subsystem == "com.splap.reader"' --last 1m | grep DEPLOY_VERIFY
```

4. **Remove verification log** after confirming deployment works.

### If No Logs Appear
- **Check subsystem**: Must be `com.splap.reader` (the bundle ID), NOT `com.example.reader`
- **Check log level**: Use `.warning` not `.info` or `.debug`
- **Trigger the code path**: Some code only runs when you open a book, tap a button, etc.
- **Verify binary updated**: Check timestamp with `ls -la .build/DerivedData/Build/Products/Debug-iphonesimulator/ReaderApp.app/ReaderApp`

## CRITICAL: Logging Standards

**USE LOGGER ONLY** - Never use NSLog, print(), or log the same event multiple times. Use the shared logger helper.

```swift
private static let logger = Log.logger(category: "feature-name")
```

**Log Levels:**
- `.debug` - Verbose details (only with `--debug` flag)
- `.info` - Important milestones (visible by default)
- `.error` - Failures

Always use `privacy: .public` to avoid redaction: `Self.logger.info("Title: \(title, privacy: .public)")`

**Physical device only:** Use `writeDebugLog()` in addition to Logger when unified logging doesn't stream.

## Debugging and Reading Logs

### Subsystem
**ALWAYS use `com.splap.reader`** - this is the bundle ID. Never use `com.example.reader`.

### For Simulator (Primary)
```bash
# Stream logs (default: info and above)
xcrun simctl spawn booted log stream --style compact --predicate 'subsystem == "com.splap.reader"'

# Add --debug to see verbose .debug logs
xcrun simctl spawn booted log stream --style compact --debug --predicate 'subsystem == "com.splap.reader"'

# Show recent logs
xcrun simctl spawn booted log show --style compact --debug --predicate 'subsystem == "com.splap.reader"' --last 5m
```

### For Physical iPad (Only When Required)
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

**Note:** NSLog() and print() may not appear in logs on newer iOS. Use file logging or os_log/Logger instead.

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
        ./scripts/run – builds and runs the app, then tails logs (NEVER EXITS!)

    IMPORTANT: ./scripts/run tails logs indefinitely after launching the app.
    Always run it in the background: `./scripts/run &` or use run_in_background parameter.

3. Headless, explicit builds
    Always use xcodebuild, never Xcode UI.
    Hard-code scheme, configuration, and simulator destination.
    Example destination: iPhone 15, iOS latest.
    This avoids simulator and scheme ambiguity.


6. Guardrails
    Add small, high-signal unit tests for all new logic.
    Snapshot tests for SwiftUI where regressions matter.
    Commit Package.resolved and pin formatter/linter versions.

## CRITICAL: UI Feature Verification

**A UI feature is NOT complete until a UI test verifies it works.**

### The Rule
- "It compiles" is NOT verification
- "It builds" is NOT verification
- "I wrote a test" is NOT verification
- **"The test ran and passed"** IS verification

**NEVER use raw xcodebuild commands. Always use ./scripts/test.**

### Available Test Commands
```bash
./scripts/test           # Unit tests (default)
./scripts/test ui        # All UI tests
./scripts/test scrubber  # Scrubber overlay toggle test
./scripts/test position  # Position persistence test
./scripts/test alignment # Page alignment test
./scripts/test all       # All tests (unit + UI)
```

### UI Test Patterns
UI tests can simulate all user interactions:
```swift
// Tap to reveal overlay
webView.tap()
sleep(1)

// Verify element appeared
XCTAssertTrue(scrubber.isHittable, "Scrubber should appear after tap")

// Interact with controls
scrubber.adjust(toNormalizedSliderPosition: 0.5)

// Swipe for pagination
webView.swipeLeft()
```

### If Tests Cannot Run
If UI tests fail to build or run, you must:
1. Fix the build/run issue first
2. OR explicitly state: "Feature is UNVERIFIED - UI tests could not be run because [reason]"

**Never claim a feature works without test evidence.**

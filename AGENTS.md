Core principle

Make the project boring and deterministic.
If a human can build/test it with one command, agents will succeed. Otherwise, they will fail unpredictably.

when you've made a change, run the app yourself so i see the result:
    use scripts/run to build and deploy the app

- Always use scripts/run script when you want to compile and run the code on the simulator. 
- Only use physical device when explicitly requested by the user

## CRITICAL: scripts/run behavior

`scripts/run` NEVER EXITS - it tails logs forever after launching the app.

**CORRECT usage:**
```bash
# Use run_in_background parameter - this is the ONLY correct way
./scripts/run   # with run_in_background: true
```

**WRONG - these will block forever:**
```bash
./scripts/run                      # blocks forever
./scripts/run 2>&1 | head -200     # blocks forever
./scripts/run &                    # won't capture build errors
sleep 30 && tail output.txt        # pointless waiting
```

After running with run_in_background, DO NOT poll the output or wait. The app will launch and you're done. Move on immediately.

**IMPORTANT**: Always use iOS 26 simulator (iPad Pro 11-inch M4).

### Simulator Ownership

`simulator-uuid` (in the project directory) is your claim ticket. Never claim a running simulator you didn't start - another agent may own it. The scripts handle this automatically.

### Throughout Session - Always Use Tracked Simulator

For ALL subsequent operations (loading books, running tests, installing app):

```bash
# Read the session simulator UDID
SIMULATOR_UDID=$(cat simulator-uuid 2>/dev/null)

# Use it for operations
xcrun simctl get_app_container "$SIMULATOR_UDID" com.splap.reader data
```


## CRITICAL: Logging Standards

**USE LOGGER ONLY** - Never use NSLog, print(), or log the same event multiple times. Use the shared logger helper.

```swift
private static let logger = Log.logger(category: "feature-name")
```

this ensures the correct bundle id for the logs: com.splap.reader

**Log Levels:**
- `.debug` - Verbose details (only with `--debug` flag)
- `.info` - Important milestones (visible by default)
- `.error` - Failures

## Debugging and Reading Logs

### Subsystem
**ALWAYS use `com.splap.reader`** - this is the bundle ID. 

### For Simulator (Primary)

# Stream logs (info and above)
xcrun simctl spawn "$SIMULATOR_UDID" log stream \
  --style compact \
  --predicate 'subsystem == "com.splap.reader"'

# Stream logs including .debug
xcrun simctl spawn "$SIMULATOR_UDID" log stream \
  --style compact \
  --debug \
  --predicate 'subsystem == "com.splap.reader"'

# Show recent logs (last 5 minutes)
xcrun simctl spawn "$SIMULATOR_UDID" log show \
  --style compact \
  --debug \
  --predicate 'subsystem == "com.splap.reader"' \
  --last 5m





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


## Test Books Location

Test epub files location: Set `TEST_BOOKS_DIR` environment variable to your epub directory

To load test books into the SESSION simulator:
```bash
# Get session simulator
SIMULATOR_UDID=$(cat simulator-uuid 2>/dev/null)

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

    See "CRITICAL: scripts/run behavior" section above for correct usage.

3. Headless, explicit builds
    Always use xcodebuild, never Xcode UI.
    Hard-code scheme, configuration, and simulator destination.
    Example destination: iPhone 15, iOS latest.
    This avoids simulator and scheme ambiguity.


6. Guardrails
    Add small, high-signal unit tests for all new logic.
    Snapshot tests for SwiftUI where regressions matter.
    Commit Package.resolved and pin formatter/linter versions.


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


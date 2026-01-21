Core principle

Make the project boring and deterministic.
If a human can build/test it with one command, agents will succeed. Otherwise, they will fail unpredictably.

when you've made a change, run the app yourself so i see the result:

# USE SCRIPTS WHENEVER POSSIBLE
- scripts/build to build the app
- scripts/lint to lint the app
- scripts/run to deploy the app


## CRITICAL: scripts/run behavior

`scripts/run` NEVER EXITS - it tails logs forever after launching the app

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

**IMPORTANT**: Always use iOS 26 simulator (iPad Pro 11-inch M5).

### Simulator Ownership

`simulator-uuid` (in the project directory) is your claim ticket. Never claim a running simulator you didn't start - another agent may own it. The scripts handle this automatically. Never start a simulator yourself, use scripts/run to start a simulator

### Simulator Logs
```bash
# Read the session simulator UDID
SIMULATOR_UDID=$(cat simulator-uuid 2>/dev/null)

# use simulator-uuid to tail simulator logs
xcrun simctl spawn "$(cat simulator-uuid)" log stream --style compact --predicate 'subsystem == "com.splap.reader"' 
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



### For Physical iPad (USB required)

Device must be connected via USB cable. Get the UDID first:
```bash
idevice_id -l
```

**User runs** (requires sudo):
```bash
sudo log collect --device-udid <UDID> --last 10m --output /tmp/device.logarchive
```

**Claude reads** (no sudo needed):
```bash
log show /tmp/device.logarchive --predicate 'subsystem == "com.splap.reader"' --style compact
```

Note: Console.app also works for live streaming (search `subsystem:com.splap.reader`).


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


## CRITICAL: Testing

**Testing is essential, but running all tests takes forever.** When developing features:
1. Find an existing test that covers the feature area, or write a new focused test
2. Run that specific test while iterating
3. Run the full unit test suite before considering work complete

**NEVER use raw xcodebuild commands. Always use ./scripts/test.**

### Running Tests
```bash
./scripts/test                        # All unit tests (default)
./scripts/test ui                     # All UI tests
./scripts/test all                    # Everything (slow!)
./scripts/test --list                 # List all available tests

# Run a specific test by name (auto-detects bundle/class):
./scripts/test testBuildAndSearchIndex
./scripts/test VectorStoreTests       # Run all tests in a class

# UI tests require ui: prefix:
./scripts/test ui:testPositionPersistence
./scripts/test ui:testScrubberAppearsOnTap
```

### Test-Driven Development
When working on a feature:
1. Run `./scripts/test --list` to see existing tests
2. Find a relevant test or write a new one
3. Iterate with `./scripts/test <testName>` until it passes
4. Run `./scripts/test` (all unit tests) before finishing

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


Core principle

Make the project boring and deterministic.
If a human can build/test it with one command, agents will succeed. Otherwise, they will fail unpredictably.

## Single Code Path Principle

Prefer one reliable way to accomplish a goal over multiple alternatives. Don't create "convenience" methods that duplicate functionality - they become maintenance burden and introduce inconsistency.

**Example**: Reading position uses CFI. Don't add alternative navigation methods like "navigate by TOC label" - it's just a worse version of the same thing. Kill the old path, don't preserve it alongside the new one.

## EPUB Reading Position: CFI is the Source of Truth

Reading positions are tracked using **EPUB CFI (Canonical Fragment Identifiers)** - the EPUB standard for fragment identification. This is the ONLY position tracking mechanism.

**CFI format**: `epubcfi(/6/N[idref]!/M/P:C)`
- `N` = spine index (even number, 1-based)
- `idref` = spine item ID
- `M/P` = DOM path within document (even numbers)
- `C` = character offset within text node

**Key files:**
- `ReaderCore/CFIParser.swift` - CFI parsing and generation
- `ReaderCore/Block.swift` - Contains `CFIPosition` struct
- `ReaderCore/ReaderPositionStore.swift` - `CFIPositionStoring` protocol
- `ReaderUI/WebPageViewController.swift` - Spine-scoped rendering, CFI JavaScript
- `ReaderUI/ReaderViewModel.swift` - CFI position loading and saving

**Spine-scoped rendering**: Only one spine item (chapter) is loaded in the WebView at a time. This eliminates layout jitter from progressive DOM injection.

**Why CFI?**
- Layout-independent: survives font size changes, device rotation, app updates
- Stable: DOM path + character offset is deterministic
- Standard: EPUB CFI is the official EPUB spec for fragment identification

when you've made a change, run the app yourself so i see the result:

# USE SCRIPTS WHENEVER POSSIBLE
- scripts/build to build the app
- scripts/lint to lint the app
- scripts/run to deploy the app


## CRITICAL: scripts/run behavior

`scripts/run` tails logs forever. Use ONLY this pattern:

```bash
./scripts/run   # with run_in_background: true
```

Read the output file afterward. Never pipe it.

**IMPORTANT**: Always use iOS 26 simulator (iPad Pro 11-inch M5).

### Clearing App Data (--clean)

Use `./scripts/run --clean` to clear all cached app data before launching. This removes:
- Search indices (`book_index.sqlite`, `vectors/`)
- AI-generated content (`concept_maps/`, `book_synopses/`, `chapter_summaries/`)
- Documents folder contents

Use this when:
- Debugging issues that might be caused by stale cached data
- Testing fresh app behavior after code changes to pagination or indexing
- Resetting the app to a clean state without reinstalling

### Simulator Ownership

`simulator-uuid` (in the project directory) is your claim ticket.

**CRITICAL RULES:**
- **NEVER modify `simulator-uuid` without explicit user permission** - this file is your claim ticket and changing it can steal another agent's simulator or cause resource conflicts
- Never claim a running simulator you didn't start - another agent may own it
- Before running `scripts/run`, check how many sims are already booted (`xcrun simctl list devices | grep Booted`) - if there are multiple, ask before booting another
- If your claimed sim is shutdown and others are running, ask before booting to avoid system overload
- Use `scripts/run` to start a simulator - never start one manually
- Check `../reader2/simulator-uuid` (and similar peer directories) to see what sims other agents own

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

**IMPORTANT: Always use `log stream` for simulators, NEVER `log show`.**
`log show` queries the log archive, but simulators don't reliably persist logs (especially debug-level). You'll get empty results. Only use `log show` for physical devices.

```bash
# Stream logs (info and above) - use this!
xcrun simctl spawn "$SIMULATOR_UDID" log stream \
  --style compact \
  --predicate 'subsystem == "com.splap.reader"'

# Stream logs including .debug
xcrun simctl spawn "$SIMULATOR_UDID" log stream \
  --style compact \
  --debug \
  --predicate 'subsystem == "com.splap.reader"'
```

To capture simulator logs, run `log stream` in a background task, then have the user reproduce the issue.





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

### CRITICAL: Verify Fixes With Tests

After fixing a bug, BEFORE telling the user it's done:
1. Check for existing tests: `./scripts/test --list | grep <keyword>`
2. If a relevant test exists, RUN IT
3. A fix is not complete until the test passes

Example workflow:
```bash
# Fixing position persistence bug
./scripts/test --list | grep -i position
# Found: ui:testPositionPersistence
./scripts/test ui:testPositionPersistence
# If it fails, the fix isn't done
```

Never declare a fix complete based only on:
- Code compiling
- Manual testing instructions for the user
- Code analysis alone

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


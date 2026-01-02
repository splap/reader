Core principle

Make the project boring and deterministic.
If a human can build/test it with one command, agents will succeed. Otherwise, they will fail unpredictably.

when you've made a change, run the app yourself so i see the result.

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

Core principle

Make the project boring and deterministic.
If a human can build/test it with one command, agents will succeed. Otherwise, they will fail unpredictably.

when you've made a change, run the simulator yourself so i see the result.

watch the simulator logs so you can see results of your changes using this command:
    xcrun simctl spawn booted log stream --style compact --debug --predicate 'subsystem == "com.example.reader" AND (category == "paging" OR category == "page-view")'

write debug logs to troubleshoot issues.

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

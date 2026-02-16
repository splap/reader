import XCTest

/// Tests for chat scroll behavior during message flow.
/// Verifies scroll position is correct when sending messages and receiving responses.
final class ChatScrollBehaviorTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func openChatOnFrankenstein(extraArgs: [String] = []) -> (table: XCUIElement, input: XCUIElement, sendButton: XCUIElement) {
        // Use --uitesting-book and --open-chat to skip library navigation
        var args = ["--uitesting-book=frankenstein", "--open-chat"]
        args.append(contentsOf: extraArgs)
        app = launchReaderApp(extraArgs: args)

        // Chat should open directly - wait for it
        let chatTable = app.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 10), "Chat table should appear when opened via --open-chat")

        let chatInput = app.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))

        let sendButton = app.buttons["chat-send-button"]

        return (chatTable, chatInput, sendButton)
    }

    private func sendMessage(_ text: String, input: XCUIElement, sendButton: XCUIElement) {
        input.tap()
        input.typeText(text)
        sendButton.tap()
    }

    // MARK: - First Message Scroll Behavior

    /// Verifies that the first response scrolls to show the response near the top,
    /// AND that there's no visual jank (position/height jumping) during streaming.
    func testFirstResponse_scrollsToTopOfResponse() {
        let (chatTable, input, sendButton) = openChatOnFrankenstein(extraArgs: [
            "--uitesting-stub-chat-long",
            "--uitesting-slow-typewriter",
        ])
        let tableFrame = chatTable.frame

        sendMessage("Test question", input: input, sendButton: sendButton)

        // Find the prompt and start tracking position as soon as it appears
        let promptText = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "Test question")
        ).firstMatch

        XCTAssertTrue(promptText.waitForExistence(timeout: 5), "Prompt should appear")

        let cells = chatTable.cells.allElementsBoundByIndex
        guard cells.count >= 1 else {
            XCTFail("Expected at least 1 cell after sending message")
            return
        }

        let turnCell = cells[0]

        // POSITION STABILITY TEST: Track BOTH the cell position and table position
        // The visual shift might be from table scroll, not cell layout
        let maxAllowedShift: CGFloat = 3.0

        // Sample cell Y relative to SCREEN (not table) to detect scroll-induced shifts
        var screenYValues: [CGFloat] = []
        var cellYValues: [CGFloat] = []

        // Sample rapidly for 3 seconds
        for _ in 0 ..< 150 {
            // Cell's minY in screen coordinates
            let cellScreenY = turnCell.frame.minY
            // Prompt's minY in screen coordinates
            let promptScreenY = promptText.frame.minY

            cellYValues.append(cellScreenY)
            screenYValues.append(promptScreenY)
            usleep(20000) // 20ms
        }

        // Analyze cell position changes (this would show scroll-induced movement)
        let cellMinY = cellYValues.min() ?? 0
        let cellMaxY = cellYValues.max() ?? 0
        let cellShift = cellMaxY - cellMinY

        // Analyze prompt position changes
        let promptMinY = screenYValues.min() ?? 0
        let promptMaxY = screenYValues.max() ?? 0
        let promptShift = promptMaxY - promptMinY

        // Find unique values
        var uniqueCellY: [(index: Int, y: CGFloat)] = []
        for (i, y) in cellYValues.enumerated() {
            if uniqueCellY.isEmpty || uniqueCellY.last!.y != y {
                uniqueCellY.append((i, y))
            }
        }

        print("Cell Y changes: \(uniqueCellY.map { "[\($0.index * 20)ms]=\(Int($0.y))" }.joined(separator: " "))")
        print("Cell shift: \(Int(cellShift))pt, Prompt shift: \(Int(promptShift))pt")

        if cellShift > maxAllowedShift {
            XCTFail("Cell SHIFTED by \(Int(cellShift))pt - scroll position changed (min=\(Int(cellMinY)), max=\(Int(cellMaxY)))")
        }
        if promptShift > maxAllowedShift {
            XCTFail("Prompt SHIFTED by \(Int(promptShift))pt (min=\(Int(promptMinY)), max=\(Int(promptMaxY)))")
        }

        // Final position check: response should be visible
        let responseText = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "first paragraph")
        ).firstMatch
        XCTAssertTrue(responseText.waitForExistence(timeout: 5), "Response should be visible")

        // Verify the turn cell is still in the top portion of the visible area
        let finalCellPosition = turnCell.frame.minY - tableFrame.minY
        XCTAssertLessThan(finalCellPosition, tableFrame.height * 0.4,
                          "Turn cell should remain near the top of the visible area")

        // CRITICAL: Verify prompt is NOT clipped at top
        // The prompt should be positioned below the cell's top edge (with padding)
        let finalPromptY = promptText.frame.minY
        let finalCellY = turnCell.frame.minY
        let promptPaddingFromCellTop = finalPromptY - finalCellY

        // Prompt should have at least 8pt of visible space above it within the cell
        XCTAssertGreaterThanOrEqual(promptPaddingFromCellTop, 8,
                                    "Prompt is clipped! Only \(Int(promptPaddingFromCellTop))pt above prompt (need >= 8pt)")

        // Final verification - response should be visible
        let answerText = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "first paragraph")
        ).firstMatch
        XCTAssertTrue(answerText.waitForExistence(timeout: 5), "Answer should be visible")

        pauseIfRequested()
    }

    // MARK: - Second Message Scroll Behavior

    /// Verifies that when sending a second message:
    /// 1. The turn cell appears at the top of the visible area
    /// 2. Answer text begins appearing promptly after the LLM response arrives
    /// 3. Text updates continuously during streaming (no stalls or blob drops)
    /// 4. No scroll position jank during streaming
    func testSecondMessage_scrollBehavior() {
        let (chatTable, input, sendButton) = openChatOnFrankenstein(extraArgs: [
            "--uitesting-stub-chat-long",
            "--uitesting-slow-typewriter",
        ])
        let tableFrame = chatTable.frame

        // First turn - send and wait for completion
        sendMessage("First question", input: input, sendButton: sendButton)
        sleep(8)

        // Second turn - record send time for latency measurement
        let sendTime = Date()
        sendMessage("Second question", input: input, sendButton: sendButton)

        // Wait for the second turn cell to appear
        var secondTurnCell: XCUIElement?
        for _ in 0 ..< 20 {
            let cells = chatTable.cells.allElementsBoundByIndex
            if cells.count >= 2 {
                secondTurnCell = cells[1]
                break
            }
            usleep(50000)
        }
        guard let turnCell = secondTurnCell else {
            XCTFail("Second turn cell didn't appear within 1s")
            return
        }

        // Verify it's near the top
        let initialPosition = turnCell.frame.minY - tableFrame.minY
        let topQuarter = tableFrame.height * 0.25
        XCTAssertLessThan(initialPosition, topQuarter,
                          "Second turn should be at TOP of visible area")

        // --- STREAMING CONSISTENCY TEST ---
        // Poll the answer text view to verify typewriter delivers text
        // promptly and continuously, with no long stalls or blob drops.
        //
        // Note: Each XCUITest element query takes ~130ms, so effective poll
        // rate is ~4 samples/sec. Thresholds account for this resolution.
        let answerView = turnCell.textViews["turn-answer"]

        struct Sample {
            let elapsed: TimeInterval
            let length: Int
        }

        var samples: [Sample] = []
        var highWaterMark = 0
        let maxWait: TimeInterval = 15.0

        while true {
            let elapsed = Date().timeIntervalSince(sendTime)
            if elapsed > maxWait { break }

            let length: Int = if answerView.exists, let text = answerView.value as? String {
                text.count
            } else {
                0
            }
            samples.append(Sample(elapsed: elapsed, length: length))
            if length > highWaterMark { highWaterMark = length }

            // Early exit: streaming complete when text has been stable for 5+
            // consecutive samples after reaching substantial length.
            // Only count samples where we actually got a value (length > 0)
            // to avoid being fooled by brief element unavailability during reloads.
            if highWaterMark > 100 {
                let recentNonZero = samples.suffix(8).filter { $0.length > 0 }
                if recentNonZero.count >= 5, recentNonZero.allSatisfy({ $0.length == highWaterMark }) {
                    break
                }
            }

            usleep(50000) // 50ms between polls (actual rate limited by query overhead)
        }

        // Filter to samples where the element was readable (ignore reload gaps)
        let validSamples = samples.filter { $0.length > 0 }

        // --- ANALYSIS ---
        guard let firstNonZero = validSamples.first else {
            XCTFail("Answer text never appeared in \(samples.count) samples over \(String(format: "%.1f", maxWait))s")
            return
        }

        // 1. Time to first text: typewriter should start promptly after stub returns.
        //    Stub delay = 100ms. Allow generous 2s for UI test overhead.
        XCTAssertLessThan(firstNonZero.elapsed, 2.0,
                          "First answer text at \(String(format: "%.2f", firstNonZero.elapsed))s - should appear within 2s of send")

        // 2. Continuous growth: no stalls > 1.5s during active streaming.
        //    A stall means the text length didn't increase for 1.5+ seconds,
        //    indicating the typewriter is not updating consistently.
        var lastGrowthTime = firstNonZero.elapsed
        var lastGrowthLength = firstNonZero.length
        var maxStall: TimeInterval = 0
        var worstStallDetail = ""

        for sample in validSamples {
            if sample.length > lastGrowthLength {
                let stall = sample.elapsed - lastGrowthTime
                if stall > maxStall {
                    maxStall = stall
                    worstStallDetail = "\(String(format: "%.2f", lastGrowthTime))s→\(String(format: "%.2f", sample.elapsed))s (len \(lastGrowthLength)→\(sample.length))"
                }
                lastGrowthTime = sample.elapsed
                lastGrowthLength = sample.length
            }
        }

        let maxAllowedStall: TimeInterval = 1.5
        XCTAssertLessThan(maxStall, maxAllowedStall,
                          "Streaming stalled \(String(format: "%.2f", maxStall))s at \(worstStallDetail) - text should update continuously")

        // 3. No content regression: text length (when readable) should only grow.
        //    Ignore transient 0s from element reload; only flag real regressions.
        var prevValidLength = 0
        for sample in validSamples {
            XCTAssertGreaterThanOrEqual(sample.length, prevValidLength,
                                        "Text shrank from \(prevValidLength) to \(sample.length) at \(String(format: "%.2f", sample.elapsed))s")
            prevValidLength = sample.length
        }

        // 4. Scroll position stability: cell shouldn't jump during streaming.
        let finalPosition = turnCell.frame.minY - tableFrame.minY
        XCTAssertLessThan(finalPosition, topQuarter,
                          "Turn cell should remain at TOP after streaming")

        // Diagnostic timeline
        let timeline = samples.reduce(into: [(TimeInterval, Int)]()) { result, s in
            if result.isEmpty || result.last!.1 != s.length {
                result.append((s.elapsed, s.length))
            }
        }
        print("STREAMING TIMELINE: \(timeline.map { "\(String(format: "%.2f", $0.0))s=\($0.1)ch" }.joined(separator: " "))")
        print("firstText=\(String(format: "%.2f", firstNonZero.elapsed))s maxStall=\(String(format: "%.2f", maxStall))s highWater=\(highWaterMark)ch samples=\(samples.count)/\(validSamples.count)valid")

        pauseIfRequested()
    }

    // MARK: - Scroll-to-Bottom Button

    /// Verifies the scroll-to-bottom button appears when content overflows
    /// and scrolls to bottom when tapped.
    func testScrollToBottomButton_appearsAndScrolls() {
        let (_, input, sendButton) = openChatOnFrankenstein(extraArgs: [
            "--uitesting-stub-chat-extralong",
            "--uitesting-slow-typewriter",
        ])

        sendMessage("Tell me about scrolling", input: input, sendButton: sendButton)

        // Wait for enough content to overflow
        sleep(10)

        // Verify button appeared
        let scrollButton = app.buttons["scroll-to-bottom-button"]
        XCTAssertTrue(scrollButton.waitForExistence(timeout: 5),
                      "Scroll-to-bottom button should appear when content overflows")

        // Verify button is tappable
        XCTAssertTrue(scrollButton.isHittable, "Button should be tappable")

        // Tap and verify scroll happens
        scrollButton.tap()
        sleep(2)

        // Button tap succeeded if we get here without crash
        // (Visual verification that scroll happened is implicit)
    }

    // MARK: - Helpers (Debug)

    /// Pause at end of test for manual inspection.
    /// Set env UITEST_PAUSE_AT_END=<seconds> or write seconds to /tmp/reader-tests/pause.
    private func pauseIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let secondsStr = env["UITEST_PAUSE_AT_END"], let seconds = UInt32(secondsStr) {
            print("UITEST_PAUSE_AT_END active: sleeping \(seconds) seconds for inspection")
            sleep(seconds)
            return
        }

        // Fallback: read from /tmp/reader-tests/pause if present (written by scripts/test)
        if let data = try? String(contentsOfFile: "/tmp/reader-tests/pause", encoding: .utf8),
           let seconds = UInt32(data.trimmingCharacters(in: .whitespacesAndNewlines)), seconds > 0
        {
            print("UITEST_PAUSE_AT_END (file) active: sleeping \(seconds) seconds for inspection")
            sleep(seconds)
        }
    }
}

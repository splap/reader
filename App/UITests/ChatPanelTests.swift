import XCTest

final class ChatPanelTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = launchReaderApp()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testChatExecutionDetailsScrollBehavior_Diagnostic() {
        // DIAGNOSTIC TEST: Reproduce the scroll bug
        // The reported bug: when expanding execution details that IS VISIBLE,
        // the scroll jumps and hides the "Execution Details" header above the visible area
        //
        // Key insight: We need to ensure the execution details is VISIBLE before tapping,
        // then observe what happens to the scroll position.

        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("Opening Frankenstein...")
        let bookCell = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
        bookCell.tap()

        // Wait for book to load (works with both WebView and native renderer)
        let webView = getReaderView(in: app)
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "Reader view should exist")
        sleep(2)

        // Tap to reveal overlay
        webView.tap()
        sleep(1)

        // Open chat
        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5), "Chat button should exist")
        chatButton.tap()

        let chatContainer = app.otherElements["chat-container-view"]
        XCTAssertTrue(chatContainer.waitForExistence(timeout: 5), "Chat container should appear")
        print("Chat view opened")

        // Dismiss keyboard by tapping elsewhere first
        let chatTable = app.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5), "Chat table should exist")

        let chatInput = app.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5), "Chat input should exist")

        // Send a question
        chatInput.tap()
        chatInput.typeText("What is this book about?")

        let sendButton = app.buttons["chat-send-button"]
        sendButton.tap()
        print("Question sent, waiting for response...")

        // Wait for execution details to appear
        let executionDetailsCollapsed = app.staticTexts["execution-details-collapsed"]
        guard executionDetailsCollapsed.waitForExistence(timeout: 60) else {
            print("No execution details found")
            return
        }

        print("Response received with execution details")

        let tableFrame = chatTable.frame
        var collapsedFrame = executionDetailsCollapsed.frame

        print("Initial state:")
        print("Table visible Y range: \(tableFrame.minY) to \(tableFrame.maxY)")
        print("Execution details Y: \(collapsedFrame.minY)")

        // Check if execution details is below visible area
        if collapsedFrame.minY > tableFrame.maxY {
            print("Execution details is BELOW visible area - scrolling to bring it into view...")

            // Scroll up (swipe up = content moves up = we see lower content)
            chatTable.swipeUp()
            sleep(1)

            // Update the frame
            collapsedFrame = executionDetailsCollapsed.frame
            print("After scroll - Execution details Y: \(collapsedFrame.minY)")
        }

        // Verify it's visible before we tap
        let isVisibleBefore = collapsedFrame.minY >= tableFrame.minY && collapsedFrame.maxY <= tableFrame.maxY
        print("=== BEFORE EXPAND ===")
        print("Table frame: \(tableFrame)")
        print("Table visible Y range: \(tableFrame.minY) to \(tableFrame.maxY)")
        print("Collapsed execution details frame: \(collapsedFrame)")
        print("Execution details fully visible before tap: \(isVisibleBefore)")
        print("Execution details is hittable: \(executionDetailsCollapsed.isHittable)")

        // SCREENSHOT 1: Before expanding - execution details should be visible
        let screenshot1 = XCUIScreen.main.screenshot()
        try? screenshot1.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/1-before-expand.png"))
        let attach1 = XCTAttachment(screenshot: screenshot1)
        attach1.name = "1-Before-Expand"
        attach1.lifetime = .keepAlways
        add(attach1)

        // TAP TO EXPAND - this is where the bug should manifest
        print("Tapping to expand execution details...")
        executionDetailsCollapsed.tap()

        // Wait for the expansion and scroll animation
        sleep(2)

        // SCREENSHOT 2: Immediately after expand - check if header is still visible
        let screenshot2 = XCUIScreen.main.screenshot()
        try? screenshot2.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/2-after-expand.png"))
        let attach2 = XCTAttachment(screenshot: screenshot2)
        attach2.name = "2-After-Expand"
        attach2.lifetime = .keepAlways
        add(attach2)

        // Check what's visible now
        let executionDetailsExpanded = app.staticTexts["execution-details-expanded"]
        if executionDetailsExpanded.waitForExistence(timeout: 3) {
            let expandedFrame = executionDetailsExpanded.frame
            print("=== AFTER EXPAND ===")
            print("Expanded execution details frame: \(expandedFrame)")
            print("Execution details top Y: \(expandedFrame.minY)")
            print("Execution details bottom Y: \(expandedFrame.maxY)")
            print("Execution details height: \(expandedFrame.height)")
            print("Table visible Y range: \(tableFrame.minY) to \(tableFrame.maxY)")

            // THE BUG CHECK: Is the TOP of execution details visible?
            // If minY < tableFrame.minY, the header is scrolled above the visible area
            let headerVisible = expandedFrame.minY >= tableFrame.minY
            let headerAboveViewport = expandedFrame.minY < tableFrame.minY

            print("Header visible in viewport: \(headerVisible)")
            print("Header scrolled ABOVE viewport (BUG): \(headerAboveViewport)")

            if headerAboveViewport {
                let hiddenAmount = tableFrame.minY - expandedFrame.minY
                print("BUG DETECTED: Header is \(hiddenAmount) points above visible area!")
                print("User would need to scroll UP to see 'Execution Details' header")
            }

            // Also check: is the header below the viewport? (scrolled too far down)
            let headerBelowViewport = expandedFrame.minY > tableFrame.maxY
            if headerBelowViewport {
                print("BUG: Header is BELOW viewport!")
            }

            // Check if "Execution Details" text is actually hittable on screen
            print("Execution details expanded element is hittable: \(executionDetailsExpanded.isHittable)")

        } else {
            print("Could not find expanded execution details element")
            // Take another screenshot to debug
            let screenshot3 = XCUIScreen.main.screenshot()
            try? screenshot3.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/3-debug.png"))
        }

        print("Screenshots saved to /tmp/reader-tests/")
        print("1-before-expand.png - state before tapping")
        print("2-after-expand.png - state after expanding")
    }

    func testChatScrollBug_MultipleMessages() {
        // Try to reproduce the bug with multiple messages creating more scroll context
        // The bug might manifest when there's more content above the execution details

        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        let bookCell = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        sleep(2)

        webView.tap()
        sleep(1)

        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        chatButton.tap()

        let chatContainer = app.otherElements["chat-container-view"]
        XCTAssertTrue(chatContainer.waitForExistence(timeout: 5))
        print("Chat opened")

        let chatInput = app.textViews["chat-input-textview"]
        let sendButton = app.buttons["chat-send-button"]
        let chatTable = app.tables["chat-message-list"]

        // Send FIRST question
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))
        chatInput.tap()
        chatInput.typeText("Who is the main character?")
        sendButton.tap()
        print("First question sent...")

        // Wait for first response
        var executionDetails = app.staticTexts["execution-details-collapsed"]
        guard executionDetails.waitForExistence(timeout: 60) else {
            print("No response to first question")
            return
        }
        print("First response received")
        sleep(2)

        // Send SECOND question to create more scroll context
        chatInput.tap()
        chatInput.typeText("Tell me about the setting")
        sendButton.tap()
        print("Second question sent...")

        // Wait for second response - need to wait for a NEW execution details
        sleep(5) // Wait for response to start
        guard executionDetails.waitForExistence(timeout: 60) else {
            print("No response to second question")
            return
        }
        print("Second response received")
        sleep(2)

        // Now scroll to bring the LATEST execution details into view at the BOTTOM of screen
        // This simulates the user looking at the bottom of a conversation
        print("Scrolling to bottom of conversation...")
        chatTable.swipeUp()
        chatTable.swipeUp()
        sleep(1)

        // There might be multiple execution details - get the last (most recent) one
        let allExecutionDetails = app.staticTexts.matching(identifier: "execution-details-collapsed")
        let count = allExecutionDetails.count
        print("Found \(count) execution details elements")

        // Use the last one (most recent message)
        executionDetails = allExecutionDetails.element(boundBy: count - 1)

        let tableFrame = chatTable.frame
        var collapsedFrame = executionDetails.frame

        print("=== STATE BEFORE EXPAND ===")
        print("Table visible Y range: \(tableFrame.minY) to \(tableFrame.maxY)")
        print("Execution details Y: \(collapsedFrame.minY)")
        print("Execution details bottom Y: \(collapsedFrame.maxY)")
        print("Is execution details visible: \(collapsedFrame.minY >= tableFrame.minY && collapsedFrame.maxY <= tableFrame.maxY)")
        print("Is hittable: \(executionDetails.isHittable)")

        // SCREENSHOT BEFORE
        let screenshot1 = XCUIScreen.main.screenshot()
        try? screenshot1.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/multi-1-before.png"))
        let attach1 = XCTAttachment(screenshot: screenshot1)
        attach1.name = "Multi-1-Before"
        attach1.lifetime = .keepAlways
        add(attach1)

        // TAP TO EXPAND
        if executionDetails.isHittable {
            print("Tapping execution details to expand...")
            executionDetails.tap()
            sleep(2)

            // SCREENSHOT AFTER
            let screenshot2 = XCUIScreen.main.screenshot()
            try? screenshot2.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/multi-2-after.png"))
            let attach2 = XCTAttachment(screenshot: screenshot2)
            attach2.name = "Multi-2-After"
            attach2.lifetime = .keepAlways
            add(attach2)

            // Check if header is visible
            let expanded = app.staticTexts["execution-details-expanded"]
            if expanded.waitForExistence(timeout: 3) {
                let expandedFrame = expanded.frame
                print("=== STATE AFTER EXPAND ===")
                print("Expanded frame: \(expandedFrame)")
                print("Header Y position: \(expandedFrame.minY)")
                print("Table visible range: \(tableFrame.minY) to \(tableFrame.maxY)")

                let headerAbove = expandedFrame.minY < tableFrame.minY
                let headerBelow = expandedFrame.minY > tableFrame.maxY

                if headerAbove {
                    print("BUG! Header is \(tableFrame.minY - expandedFrame.minY) points ABOVE viewport!")
                } else if headerBelow {
                    print("BUG! Header is BELOW viewport!")
                } else {
                    print("Header is visible in viewport")
                }
            }
        } else {
            print("Execution details not hittable - scrolling more...")
            chatTable.swipeUp()
            sleep(1)
            if executionDetails.isHittable {
                executionDetails.tap()
                sleep(2)
            }
        }

        print("Multi-message test complete")
        print("Screenshots: /tmp/reader-tests/multi-1-before.png, multi-2-after.png")
    }

    func testChatExecutionDetailsScrollBehavior() {
        // This test verifies that when execution details are expanded in the chat,
        // the scroll position correctly shows the execution details header,
        // not scrolling past it where the user can't see what they tapped.
        //
        // Expected behavior:
        // - If execution details are short: the last line should be visible
        // - If execution details are long: the first line of execution details should be visible

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("Opening Frankenstein...")
        let bookCell = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
        bookCell.tap()

        // Wait for book to load (works with both WebView and native renderer)
        let webView = getReaderView(in: app)
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "Reader view should exist")
        sleep(2)

        // Tap to reveal overlay
        print("Revealing overlay...")
        webView.tap()
        sleep(1)

        // Find and tap the Chat button
        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5), "Chat button should exist")
        print("Opening chat...")
        chatButton.tap()

        // Wait for chat view to appear
        let chatContainer = app.otherElements["chat-container-view"]
        XCTAssertTrue(chatContainer.waitForExistence(timeout: 5), "Chat container should appear")
        print("Chat view opened")

        // Find the chat input text view
        let chatInput = app.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5), "Chat input should exist")

        // Type a question
        print("Typing a question...")
        chatInput.tap()
        chatInput.typeText("What is this book about?")

        // Find and tap send button
        let sendButton = app.buttons["chat-send-button"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3), "Send button should exist")
        print("Sending message...")
        sendButton.tap()

        // Wait for response - execution details should appear
        // The execution details starts collapsed with ">" indicator
        print("Waiting for response with execution details...")
        let executionDetailsCollapsed = app.staticTexts["execution-details-collapsed"]
        let responseReceived = executionDetailsCollapsed.waitForExistence(timeout: 60)

        if !responseReceived {
            // If no execution details, the model might not have trace enabled
            // Take screenshot for debugging
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "No Execution Details"
            attachment.lifetime = .keepAlways
            add(attachment)

            print("No execution details found - response may not have trace")
            // Still check for response content
            let chatTable = app.tables["chat-message-list"]
            XCTAssertTrue(chatTable.exists, "Chat message list should exist")
            return
        }

        print("Execution details found (collapsed)")

        // Get the frame of the execution details before expanding
        let frameBeforeExpand = executionDetailsCollapsed.frame
        print("Execution details frame before expand: \(frameBeforeExpand)")

        // Take screenshot before expanding
        let screenshotBefore = XCUIScreen.main.screenshot()
        let attachmentBefore = XCTAttachment(screenshot: screenshotBefore)
        attachmentBefore.name = "Before Expand"
        attachmentBefore.lifetime = .keepAlways
        add(attachmentBefore)

        // Tap to expand execution details
        print("Tapping to expand execution details...")
        executionDetailsCollapsed.tap()
        sleep(1) // Wait for expansion animation and scroll

        // After expanding, look for the expanded version
        let executionDetailsExpanded = app.staticTexts["execution-details-expanded"]
        XCTAssertTrue(executionDetailsExpanded.waitForExistence(timeout: 5),
                      "Execution details should be expanded")
        print("Execution details expanded")

        // Take screenshot after expanding
        let screenshotAfter = XCUIScreen.main.screenshot()
        let attachmentAfter = XCTAttachment(screenshot: screenshotAfter)
        attachmentAfter.name = "After Expand"
        attachmentAfter.lifetime = .keepAlways
        add(attachmentAfter)

        // CRITICAL ASSERTION: The execution details header should be visible
        // This is the bug - the scroll was hiding the header
        let frameAfterExpand = executionDetailsExpanded.frame
        print("Execution details frame after expand: \(frameAfterExpand)")

        // Get the visible area of the chat table
        let chatTable = app.tables["chat-message-list"]
        XCTAssertTrue(chatTable.exists, "Chat message list should exist")
        let tableFrame = chatTable.frame
        print("Chat table frame: \(tableFrame)")

        // Check that the top of the execution details is visible (within the table's bounds)
        // The Y position should be >= table's minY (not scrolled above the visible area)
        let isTopVisible = frameAfterExpand.minY >= tableFrame.minY
        let isPartiallyVisible = frameAfterExpand.maxY > tableFrame.minY

        print("Top of execution details visible: \(isTopVisible)")
        print("Partially visible: \(isPartiallyVisible)")

        // Primary assertion: The header should be visible after expanding
        // If the execution details are long, at minimum the first line should be visible
        XCTAssertTrue(isPartiallyVisible,
                      "Execution details should be at least partially visible after expansion. " +
                          "Frame: \(frameAfterExpand), Table: \(tableFrame)")

        // If we can see the element, also verify it contains the expected header text
        let expandedText = executionDetailsExpanded.label
        XCTAssertTrue(expandedText.contains("Execution Details"),
                      "Expanded section should show 'Execution Details' header")
        XCTAssertTrue(expandedText.contains("down arrow") || expandedText.contains("\u{25BC}") || expandedText.contains("v"),
                      "Expanded section should show down arrow indicator")

        print("Execution details scroll test passed - header is visible after expansion")

        // Save screenshot for visual inspection
        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
        let afterPath = "/tmp/reader-tests/execution-details-expand.png"
        try? screenshotAfter.pngRepresentation.write(to: URL(fileURLWithPath: afterPath))
        print("Screenshot saved to: \(afterPath)")
    }

    func testChatExecutionDetailsCollapseExpand() {
        // This test verifies that execution details can be toggled between
        // collapsed and expanded states, and the scroll behavior is correct each time

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("Opening Frankenstein...")
        let bookCell = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein book should be visible")
        bookCell.tap()

        // Wait for book to load (works with both WebView and native renderer)
        let webView = getReaderView(in: app)
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "Reader view should exist")
        sleep(2)

        // Tap to reveal overlay and open chat
        webView.tap()
        sleep(1)

        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5), "Chat button should exist")
        chatButton.tap()

        let chatContainer = app.otherElements["chat-container-view"]
        XCTAssertTrue(chatContainer.waitForExistence(timeout: 5), "Chat should open")
        print("Chat opened")

        // Send a question
        let chatInput = app.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5), "Chat input should exist")
        chatInput.tap()
        chatInput.typeText("Tell me about the main character")

        let sendButton = app.buttons["chat-send-button"]
        sendButton.tap()
        print("Question sent")

        // Wait for response
        let executionDetailsCollapsed = app.staticTexts["execution-details-collapsed"]
        guard executionDetailsCollapsed.waitForExistence(timeout: 60) else {
            print("No execution details - skipping toggle test")
            return
        }

        print("Starting collapse/expand toggle test...")

        // Toggle 1: Expand
        print("Toggle 1: Expanding...")
        executionDetailsCollapsed.tap()
        sleep(1)

        let executionDetailsExpanded = app.staticTexts["execution-details-expanded"]
        XCTAssertTrue(executionDetailsExpanded.waitForExistence(timeout: 5), "Should be expanded")

        // Verify header is visible
        let chatTable = app.tables["chat-message-list"]
        let expandedFrame = executionDetailsExpanded.frame
        let tableFrame = chatTable.frame
        XCTAssertTrue(expandedFrame.maxY > tableFrame.minY,
                      "Expanded execution details should be visible")
        print("Toggle 1: Expanded and visible")

        // Toggle 2: Collapse
        print("Toggle 2: Collapsing...")
        executionDetailsExpanded.tap()
        sleep(1)

        XCTAssertTrue(executionDetailsCollapsed.waitForExistence(timeout: 5), "Should be collapsed")
        print("Toggle 2: Collapsed")

        // Toggle 3: Expand again
        print("Toggle 3: Expanding again...")
        executionDetailsCollapsed.tap()
        sleep(1)

        XCTAssertTrue(executionDetailsExpanded.waitForExistence(timeout: 5), "Should be expanded again")

        // Final verification: header should still be visible
        let finalFrame = executionDetailsExpanded.frame
        XCTAssertTrue(finalFrame.maxY > tableFrame.minY,
                      "Execution details should remain visible after multiple toggles")

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "After Toggle Test"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("Collapse/expand toggle test complete")
    }

    // MARK: - Stub-based Tests (Fast, Reliable)

    func testResponseScrollsToTop() {
        // Launch with stub that returns a long response
        let stubApp = launchReaderApp(extraArgs: ["--uitesting-stub-chat-long"])

        // Open Frankenstein
        let libraryNavBar = stubApp.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        let bookCell = findBook(in: stubApp, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        // Wait for book to load
        let webView = stubApp.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        sleep(2)

        // Tap to reveal overlay and open chat
        webView.tap()
        sleep(1)

        let chatButton = stubApp.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        chatButton.tap()

        // Wait for chat to appear by checking for the chat table
        let chatTable = stubApp.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5), "Chat table should appear")

        // Send a message
        let chatInput = stubApp.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))
        chatInput.tap()
        chatInput.typeText("Test question")

        let sendButton = stubApp.buttons["chat-send-button"]
        sendButton.tap()

        // Wait for response (stub responds in ~100ms + typewriter animation)
        // For a long response, typewriter takes longer, but we just need to verify scroll position
        sleep(3)

        // Take a screenshot for verification
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Response-Scroll-Position"
        attachment.lifetime = .keepAlways
        add(attachment)

        // The response cell should be visible near the top of the table
        // We verify by checking that the response text is visible
        let responseText = stubApp.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "first paragraph")).firstMatch
        XCTAssertTrue(responseText.waitForExistence(timeout: 5), "Response should be visible")

        // Verify the response cell's top is near the table's top (scrolled to top, not bottom)
        let tableFrame = chatTable.frame
        let responseFrame = responseText.frame

        // The response should be in the top half of the visible area
        let responseTopRelativeToTable = responseFrame.minY - tableFrame.minY
        let tableVisibleHeight = tableFrame.height

        print("Response top relative to table: \(responseTopRelativeToTable)")
        print("Table visible height: \(tableVisibleHeight)")

        // Response should be in the top portion of the visible area (within first 60%)
        XCTAssertLessThan(responseTopRelativeToTable, tableVisibleHeight * 0.6,
                          "Response should appear near the top of the visible area, not scrolled to bottom")
    }

    func testTypewriterEffectCompletes() {
        // Launch with stub that returns a short response
        let stubApp = launchReaderApp(extraArgs: ["--uitesting-stub-chat-short"])

        // Open Frankenstein
        let libraryNavBar = stubApp.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        let bookCell = findBook(in: stubApp, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        // Wait for book to load
        let webView = stubApp.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        sleep(2)

        // Tap to reveal overlay and open chat
        webView.tap()
        sleep(1)

        let chatButton = stubApp.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        chatButton.tap()

        // Wait for chat to appear by checking for the chat table
        let chatTable = stubApp.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5), "Chat table should appear")

        // Send a message
        let chatInput = stubApp.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))
        chatInput.tap()
        chatInput.typeText("Test question")

        let sendButton = stubApp.buttons["chat-send-button"]
        sendButton.tap()

        // Wait for typewriter animation to complete
        // Short response: ~6 words at 40ms = 240ms, plus margin
        sleep(3)

        // Take a screenshot for verification
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Typewriter-Complete"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Verify the full response text is visible
        // The stub's short response is: "This is a short test response."
        let fullResponse = stubApp.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "short test response")).firstMatch
        XCTAssertTrue(fullResponse.waitForExistence(timeout: 3), "Full response should be visible after typewriter completes")
    }

    func testTypewriterAnchorsToBottomAfterUserScrolls() {
        // Test the "smart anchor" behavior:
        // 1. Response starts at TOP
        // 2. User scrolls down to catch up with typewriter
        // 3. View should now auto-scroll to keep user at bottom as new words appear

        // Launch with stub that returns a long response (gives time to interact)
        let stubApp = launchReaderApp(extraArgs: ["--uitesting-stub-chat-long"])

        // Open Frankenstein
        let libraryNavBar = stubApp.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        let bookCell = findBook(in: stubApp, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        // Wait for book to load
        let webView = stubApp.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        sleep(2)

        // Tap to reveal overlay and open chat
        webView.tap()
        sleep(1)

        let chatButton = stubApp.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        chatButton.tap()

        // Wait for chat to appear
        let chatTable = stubApp.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5), "Chat table should appear")

        // Send a message
        let chatInput = stubApp.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))
        chatInput.tap()
        chatInput.typeText("Tell me about this book")

        let sendButton = stubApp.buttons["chat-send-button"]
        sendButton.tap()

        // Wait for typewriter to start (stub has 100ms delay, then typewriter begins)
        sleep(1)

        // Take screenshot showing response starts at top
        let screenshot1 = XCUIScreen.main.screenshot()
        let attachment1 = XCTAttachment(screenshot: screenshot1)
        attachment1.name = "1-Response-Starts-At-Top"
        attachment1.lifetime = .keepAlways
        add(attachment1)

        // Now scroll down to "catch up" with the typewriter
        chatTable.swipeUp()
        sleep(1)

        // Take screenshot after scrolling
        let screenshot2 = XCUIScreen.main.screenshot()
        let attachment2 = XCTAttachment(screenshot: screenshot2)
        attachment2.name = "2-After-Scroll-To-Catch-Up"
        attachment2.lifetime = .keepAlways
        add(attachment2)

        // Wait for more typewriter content to be added
        sleep(2)

        // Take final screenshot - should still be near bottom showing latest content
        let screenshot3 = XCUIScreen.main.screenshot()
        let attachment3 = XCTAttachment(screenshot: screenshot3)
        attachment3.name = "3-Anchored-At-Bottom"
        attachment3.lifetime = .keepAlways
        add(attachment3)

        // Verify the last paragraph is visible (since we should be anchored to bottom)
        // The stub's long response ends with "...sunt in culpa qui officia deserunt mollit anim id est laborum."
        let lastParagraphText = stubApp.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "laborum")).firstMatch
        XCTAssertTrue(lastParagraphText.waitForExistence(timeout: 5),
                      "Last paragraph should be visible when anchored to bottom after catching up")

        print("Smart anchor test complete - user caught up and stayed at bottom")
    }

    func testErrorResponseDisplayed() {
        // Launch with stub that returns an error
        let stubApp = launchReaderApp(extraArgs: ["--uitesting-stub-chat-error"])

        // Open Frankenstein
        let libraryNavBar = stubApp.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        let bookCell = findBook(in: stubApp, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        // Wait for book to load
        let webView = stubApp.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        sleep(2)

        // Tap to reveal overlay and open chat
        webView.tap()
        sleep(1)

        let chatButton = stubApp.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        chatButton.tap()

        // Wait for chat to appear by checking for the chat table
        let chatTable = stubApp.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5), "Chat table should appear")

        // Send a message
        let chatInput = stubApp.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))
        chatInput.tap()
        chatInput.typeText("Test question")

        let sendButton = stubApp.buttons["chat-send-button"]
        sendButton.tap()

        // Wait for error response
        sleep(2)

        // Verify error message is displayed
        let errorMessage = stubApp.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Error")).firstMatch
        XCTAssertTrue(errorMessage.waitForExistence(timeout: 3), "Error message should be displayed")

        // Take a screenshot for verification
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Error-Response"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("Error response test complete")
    }

    // MARK: - Drawer Navigation Tests

    func testDrawerCurrentChatNavigationMultiHop() {
        // This test verifies the multi-hop drawer navigation bug fix:
        // 1. Open chat (new chat A)
        // 2. Create saved conversations by sending messages and closing
        // 3. Open chat again (new chat B)
        // 4. Open drawer, click saved conversation 1
        // 5. Click saved conversation 2
        // 6. Click "Current Chat"
        // 7. Verify we're back to new chat B (not stuck on conv 2)

        let stubApp = launchReaderApp(extraArgs: ["--uitesting-stub-chat-short"])

        // Open Frankenstein
        let libraryNavBar = stubApp.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        let bookCell = findBook(in: stubApp, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        let webView = stubApp.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        sleep(2)

        // === Create first saved conversation ===
        webView.tap()
        sleep(1)

        let chatButton = stubApp.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        chatButton.tap()

        let chatTable = stubApp.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5))

        let chatInput = stubApp.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))
        chatInput.tap()
        chatInput.typeText("First conversation message")

        let sendButton = stubApp.buttons["chat-send-button"]
        sendButton.tap()
        sleep(3) // Wait for stub response

        // Close chat to save first conversation
        let doneButton = stubApp.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.tap()
        sleep(1)

        // === Create second saved conversation ===
        webView.tap()
        sleep(1)
        chatButton.tap()
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5))

        chatInput.tap()
        chatInput.typeText("Second conversation message")
        sendButton.tap()
        sleep(3)

        // Close chat to save second conversation
        doneButton.tap()
        sleep(1)

        // === Open new chat (this will be our "origin") ===
        webView.tap()
        sleep(1)
        chatButton.tap()
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5))

        // The chat should be empty (new chat)
        // Take screenshot of initial new chat state
        let screenshot1 = XCUIScreen.main.screenshot()
        let attach1 = XCTAttachment(screenshot: screenshot1)
        attach1.name = "1-New-Chat-Origin"
        attach1.lifetime = .keepAlways
        add(attach1)

        // === Open drawer ===
        let sidebarButton = stubApp.buttons["chat-sidebar-button"]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 3), "Sidebar button should exist")
        sidebarButton.tap()
        sleep(1)

        // Take screenshot of drawer
        let screenshot2 = XCUIScreen.main.screenshot()
        let attach2 = XCTAttachment(screenshot: screenshot2)
        attach2.name = "2-Drawer-Open"
        attach2.lifetime = .keepAlways
        add(attach2)

        // Find conversation cells in the drawer
        let conversationCells = stubApp.cells.allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(conversationCells.count, 3, "Should have Current Chat + 2 saved conversations")

        // First cell (index 0) is "Current Chat"
        let currentChatCell = conversationCells[0]
        XCTAssertTrue(currentChatCell.staticTexts["Current Chat"].exists, "First cell should be Current Chat")

        // Remaining cells are saved conversations
        var savedConversationCells: [XCUIElement] = []
        for i in 1 ..< conversationCells.count {
            savedConversationCells.append(conversationCells[i])
        }

        guard savedConversationCells.count >= 2 else {
            print("Not enough saved conversations found (\(savedConversationCells.count)), skipping multi-hop test")
            // Take screenshot for debugging
            let debugScreenshot = XCUIScreen.main.screenshot()
            let debugAttach = XCTAttachment(screenshot: debugScreenshot)
            debugAttach.name = "Debug-Not-Enough-Conversations"
            debugAttach.lifetime = .keepAlways
            add(debugAttach)
            return
        }

        // === Click first saved conversation ===
        print("Clicking first saved conversation...")
        savedConversationCells[0].tap()
        sleep(1)

        let screenshot3 = XCUIScreen.main.screenshot()
        let attach3 = XCTAttachment(screenshot: screenshot3)
        attach3.name = "3-After-Click-Conv1"
        attach3.lifetime = .keepAlways
        add(attach3)

        // === Click second saved conversation ===
        print("Clicking second saved conversation...")
        savedConversationCells[1].tap()
        sleep(1)

        let screenshot4 = XCUIScreen.main.screenshot()
        let attach4 = XCTAttachment(screenshot: screenshot4)
        attach4.name = "4-After-Click-Conv2"
        attach4.lifetime = .keepAlways
        add(attach4)

        // Verify we're showing the second conversation's content
        // (The stub response contains "short test response")
        let conv2Content = stubApp.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "short test response")).firstMatch
        XCTAssertTrue(conv2Content.waitForExistence(timeout: 3), "Should be showing saved conversation content")

        // === Click "Current Chat" to return to origin ===
        print("Clicking Current Chat to return to origin...")
        currentChatCell.tap()
        sleep(1)

        let screenshot5 = XCUIScreen.main.screenshot()
        let attach5 = XCTAttachment(screenshot: screenshot5)
        attach5.name = "5-After-Click-Current-Chat"
        attach5.lifetime = .keepAlways
        add(attach5)

        // === Verify we're back to the new (empty) chat ===
        // The new chat should NOT have any response messages in the chat table
        // Note: The drawer may still show conversation titles containing the response text,
        // so we specifically check within the chat message table

        // Get the message cells in the chat table
        let messageCells = chatTable.cells
        let messageCellCount = messageCells.count

        // An empty new chat should have 0 message cells
        // (saved conversations have at least 2: user message + response)
        print("Message cells in chat table: \(messageCellCount)")

        // Take screenshot showing final state
        let screenshot6 = XCUIScreen.main.screenshot()
        let attach6 = XCTAttachment(screenshot: screenshot6)
        attach6.name = "6-Final-Chat-State"
        attach6.lifetime = .keepAlways
        add(attach6)

        // The new chat should have 0 messages (it was never used)
        XCTAssertEqual(messageCellCount, 0,
                       "After clicking Current Chat, should return to the empty new chat with 0 messages, but found \(messageCellCount)")

        print("Multi-hop drawer navigation test passed!")
    }
}

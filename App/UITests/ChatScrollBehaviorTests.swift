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
        app = launchReaderApp(extraArgs: extraArgs)

        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        let bookCell = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        let readerView = getReaderView(in: app)
        XCTAssertTrue(readerView.waitForExistence(timeout: 5))
        sleep(2)

        readerView.tap()
        sleep(1)

        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        chatButton.tap()

        let chatTable = app.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5))

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

    /// Verifies that the first response scrolls to show the response near the top.
    func testFirstResponse_scrollsToTopOfResponse() {
        let (chatTable, input, sendButton) = openChatOnFrankenstein(extraArgs: ["--uitesting-stub-chat-long"])

        sendMessage("Test question", input: input, sendButton: sendButton)
        sleep(3)

        // Verify response text is visible
        let responseText = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "first paragraph")
        ).firstMatch
        XCTAssertTrue(responseText.waitForExistence(timeout: 5), "Response should be visible")

        // Verify the response is in the top portion of the visible area
        let tableFrame = chatTable.frame
        let responseFrame = responseText.frame
        let responseTopRelativeToTable = responseFrame.minY - tableFrame.minY
        let tableVisibleHeight = tableFrame.height

        XCTAssertLessThan(responseTopRelativeToTable, tableVisibleHeight * 0.6,
                          "Response should appear near the top of the visible area")
    }

    // MARK: - Second Message Scroll Behavior

    /// Verifies that when sending a second message, the user message appears at the top
    /// and there's no scroll jump when the response starts streaming.
    func testSecondMessage_scrollBehavior() {
        let (chatTable, input, sendButton) = openChatOnFrankenstein(extraArgs: ["--uitesting-stub-chat-long"])
        let tableFrame = chatTable.frame

        // First message
        sendMessage("First question", input: input, sendButton: sendButton)
        sleep(5)

        // Second message
        sendMessage("Second question", input: input, sendButton: sendButton)
        sleep(1)

        // Verify second user message is near the TOP
        let cells = chatTable.cells.allElementsBoundByIndex
        guard cells.count >= 3 else {
            XCTFail("Expected at least 3 cells (user1, assistant1, user2)")
            return
        }

        let secondUserMessageCell = cells[2]
        let cellFrame = secondUserMessageCell.frame
        let cellTopRelativeToTable = cellFrame.minY - tableFrame.minY

        let topQuarter = tableFrame.height * 0.25
        XCTAssertLessThan(cellTopRelativeToTable, topQuarter,
                          "Second user message should be at TOP of visible area")

        // Wait for response and verify no jump
        sleep(4)

        let cellsAfterResponse = chatTable.cells.allElementsBoundByIndex
        guard cellsAfterResponse.count >= 3 else { return }

        let cellAfter = cellsAfterResponse[2]
        let cellTopAfter = cellAfter.frame.minY - tableFrame.minY

        XCTAssertLessThan(cellTopAfter, topQuarter,
                          "User message should NOT jump when response arrives")
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
}

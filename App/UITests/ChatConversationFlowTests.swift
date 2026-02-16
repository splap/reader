import XCTest

/// Tests for the core chat conversation flow: sending messages and receiving responses.
/// These tests verify the fundamental chat interaction patterns work correctly.
final class ChatConversationFlowTests: XCTestCase {
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

    // MARK: - Send/Receive Flow

    /// Verifies that sending a message produces a response with typewriter animation completing.
    func testSendMessage_receivesResponse() {
        let (_, input, sendButton) = openChatOnFrankenstein(extraArgs: ["--uitesting-stub-chat-short"])

        sendMessage("Test question", input: input, sendButton: sendButton)

        // Wait for typewriter animation to complete (~3s for short response)
        sleep(3)

        // Verify the full response text is visible
        let fullResponse = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "short test response")
        ).firstMatch
        XCTAssertTrue(fullResponse.waitForExistence(timeout: 5),
                      "Response should be visible after typewriter completes")
    }

    /// Verifies that error responses are displayed to the user.
    func testSendMessage_errorDisplayed() {
        let (_, input, sendButton) = openChatOnFrankenstein(extraArgs: ["--uitesting-stub-chat-error"])

        sendMessage("Test question", input: input, sendButton: sendButton)
        sleep(2)

        let errorMessage = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "Error")
        ).firstMatch
        XCTAssertTrue(errorMessage.waitForExistence(timeout: 3),
                      "Error message should be displayed")
    }

    // MARK: - Multi-Message Conversations

    /// Verifies a multi-turn conversation works correctly.
    /// Note: With turn-based architecture, each turn (prompt + answer) is ONE cell.
    func testMultipleMessages_conversationBuilds() {
        let (chatTable, input, sendButton) = openChatOnFrankenstein(extraArgs: ["--uitesting-stub-chat-short"])

        // First turn
        sendMessage("First question", input: input, sendButton: sendButton)
        sleep(3)

        // Verify first response
        let firstResponse = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "short test response")
        ).firstMatch
        XCTAssertTrue(firstResponse.waitForExistence(timeout: 5))

        // Second turn
        sendMessage("Follow-up question", input: input, sendButton: sendButton)
        sleep(3)

        // Verify conversation has 2 cells (turn1, turn2)
        // Each turn contains both prompt and answer in a single cell
        let cells = chatTable.cells.allElementsBoundByIndex
        XCTAssertEqual(cells.count, 2, "Should have 2 turn cells after 2 exchanges")
    }
}

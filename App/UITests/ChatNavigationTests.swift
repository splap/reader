import XCTest

/// Tests for chat navigation: drawer, saved conversations, and switching between chats.
final class ChatNavigationTests: XCTestCase {
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

    private func launchAndOpenBook() -> XCUIElement {
        app = launchReaderApp(extraArgs: ["--uitesting-stub-chat-short"])

        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        let bookCell = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        let readerView = getReaderView(in: app)
        XCTAssertTrue(readerView.waitForExistence(timeout: 5))
        sleep(2)

        return readerView
    }

    private func openChat(from readerView: XCUIElement) -> (table: XCUIElement, input: XCUIElement, sendButton: XCUIElement) {
        // Only tap if chat button isn't visible
        let chatButton = app.buttons["Chat"]
        if !chatButton.exists {
            readerView.tap()
            sleep(1)
        }

        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        chatButton.tap()

        let chatTable = app.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5))

        let chatInput = app.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))

        let sendButton = app.buttons["chat-send-button"]

        return (chatTable, chatInput, sendButton)
    }

    private func closeChat() {
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.tap()
        sleep(1)
    }

    private func createSavedConversation(readerView: XCUIElement, message: String) {
        let (_, input, sendButton) = openChat(from: readerView)

        input.tap()
        input.typeText(message)
        sendButton.tap()
        sleep(3)

        closeChat()
    }

    // MARK: - Drawer Navigation

    /// Verifies drawer shows saved conversations and "Current Chat" option.
    func testDrawer_showsConversationList() {
        let readerView = launchAndOpenBook()

        // Create a saved conversation
        createSavedConversation(readerView: readerView, message: "Test message for saving")

        // Open new chat
        let _ = openChat(from: readerView)

        // Open drawer
        let sidebarButton = app.buttons["Conversations"]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 3))
        sidebarButton.tap()
        sleep(1)

        // Verify drawer contents
        let conversationCells = app.cells.allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(conversationCells.count, 2,
                                    "Should have Current Chat + at least 1 saved conversation")

        let currentChatCell = conversationCells[0]
        XCTAssertTrue(currentChatCell.staticTexts["Current Chat"].exists,
                      "First cell should be Current Chat")
    }

    /// Verifies navigating between multiple saved conversations works correctly,
    /// and returning to "Current Chat" shows the empty new chat.
    func testDrawer_multiHopNavigation() {
        let readerView = launchAndOpenBook()

        // Create two saved conversations
        createSavedConversation(readerView: readerView, message: "First conversation")
        createSavedConversation(readerView: readerView, message: "Second conversation")

        // Open new chat (this is our origin)
        let (chatTable, _, _) = openChat(from: readerView)

        // Open drawer
        let sidebarButton = app.buttons["Conversations"]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 3))
        sidebarButton.tap()
        sleep(1)

        let conversationCells = app.cells.allElementsBoundByIndex
        guard conversationCells.count >= 3 else {
            XCTFail("Expected Current Chat + 2 saved conversations")
            return
        }

        let currentChatCell = conversationCells[0]

        // Collect saved conversation cells
        var savedCells: [XCUIElement] = []
        for i in 1 ..< conversationCells.count {
            savedCells.append(conversationCells[i])
        }

        // Navigate: saved1 -> saved2 -> Current Chat
        savedCells[0].tap()
        sleep(1)

        savedCells[1].tap()
        sleep(1)

        // Verify we're showing saved conversation content
        let savedContent = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "short test response")
        ).firstMatch
        XCTAssertTrue(savedContent.waitForExistence(timeout: 3))

        // Return to Current Chat
        currentChatCell.tap()
        sleep(1)

        // Verify we're back to empty new chat
        let messageCellCount = chatTable.cells.count
        XCTAssertEqual(messageCellCount, 0,
                       "Current Chat should be empty with 0 messages")
    }

    /// Verifies that closing chat saves the conversation for later access.
    func testCloseChat_savesConversation() {
        let readerView = launchAndOpenBook()

        // Start a conversation
        let (_, input, sendButton) = openChat(from: readerView)
        input.tap()
        input.typeText("Message to save")
        sendButton.tap()
        sleep(3)

        // Close chat
        closeChat()

        // Reopen chat - should start fresh
        let (chatTable, _, _) = openChat(from: readerView)

        // New chat should be empty
        XCTAssertEqual(chatTable.cells.count, 0, "New chat should be empty")

        // But drawer should have the saved conversation
        let sidebarButton = app.buttons["Conversations"]
        sidebarButton.tap()
        sleep(1)

        let cells = app.cells.allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(cells.count, 2,
                                    "Should have Current Chat + saved conversation")
    }
}

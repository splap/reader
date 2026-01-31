import Foundation

/// Stub agent service for UI testing with preset response modes
public actor StubAgentService: AgentServiceProtocol {
    /// Response mode for the stub
    public enum Mode: String {
        case short // Quick verification
        case long // Scroll testing - multiple paragraphs
        case extraLong // Extended scroll testing - many paragraphs for typewriter observation
        case error // Error handling
    }

    private let mode: Mode

    public init(mode: Mode) {
        self.mode = mode
    }

    public func chat(
        message _: String,
        context _: BookContext,
        history: [AgentMessage],
        selectionContext _: String?,
        selectionBlockId _: String?,
        selectionSpineItemId _: String?
    ) async throws -> (response: AgentResponse, updatedHistory: [AgentMessage]) {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        switch mode {
        case .short:
            let response = AgentResponse(content: "This is a short test response.")
            var updatedHistory = history
            updatedHistory.append(AgentMessage(role: .assistant, content: response.content))
            return (response: response, updatedHistory: updatedHistory)

        case .long:
            let response = AgentResponse(content: Self.longResponse)
            var updatedHistory = history
            updatedHistory.append(AgentMessage(role: .assistant, content: response.content))
            return (response: response, updatedHistory: updatedHistory)

        case .extraLong:
            let response = AgentResponse(content: Self.extraLongResponse)
            var updatedHistory = history
            updatedHistory.append(AgentMessage(role: .assistant, content: response.content))
            return (response: response, updatedHistory: updatedHistory)

        case .error:
            throw OpenRouterError.invalidResponse
        }
    }

    private static let longResponse = """
    This is the first paragraph of a long test response. It contains enough text to ensure \
    the response will overflow the visible chat area on any device size. The content is \
    designed to test scroll behavior in the chat interface.

    The second paragraph continues with more content. We need multiple paragraphs to properly \
    test the scroll behavior where the response should appear at the top, not scrolled to \
    bottom. This paragraph adds additional height to the response.

    Here is the third paragraph. Lorem ipsum dolor sit amet, consectetur adipiscing elit. \
    Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim \
    veniam, quis nostrud exercitation ullamco laboris.

    The fourth paragraph adds even more content. Ut enim ad minim veniam, quis nostrud \
    exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure \
    dolor in reprehenderit in voluptate velit esse cillum dolore.

    Finally, the fifth paragraph concludes. Duis aute irure dolor in reprehenderit in \
    voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat \
    cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
    """

    private static let extraLongResponse = """
    **Paragraph 1: Introduction**

    This is an extra-long test response designed specifically to observe typewriter scroll \
    behavior over an extended period. The typewriter effect reveals characters gradually, \
    and we need enough content to test how scrolling behaves as the response grows beyond \
    the visible area.

    **Paragraph 2: The Setup**

    When a chat response begins, it starts empty and characters are revealed one by one or \
    in small batches. Initially, the entire response fits within the visible chat area, so \
    no scrolling is needed. The user can see all the content as it appears.

    **Paragraph 3: The Overflow Point**

    At some point during the typewriter animation, the response content grows tall enough \
    to overflow the visible area. This is the critical moment where scroll behavior becomes \
    important. The view should automatically scroll to keep the newest content visible.

    **Paragraph 4: Auto-Scroll Behavior**

    Good auto-scroll behavior means the view smoothly follows the typewriter as new content \
    appears. The user should always be able to see the latest text being typed. However, the \
    scrolling should feel natural, not jarring or jumpy.

    **Paragraph 5: User Scroll Interruption**

    If the user manually scrolls up to read earlier content, the auto-scroll should stop. \
    The view should respect the user's scroll position and not fight against their intent. \
    This is crucial for a good user experience.

    **Paragraph 6: Resuming Auto-Scroll**

    When the user scrolls back down to the bottom of the content, auto-scroll should resume. \
    The system needs to detect when the user has returned to "following" mode and start \
    tracking new content again.

    **Paragraph 7: Edge Cases**

    Various edge cases need handling: rapid scrolling, scrolling during layout updates, \
    content height changes, and the transition from typewriter animation to final state. \
    Each of these can potentially cause scroll position issues.

    **Paragraph 8: Performance Considerations**

    The typewriter effect updates the text view content frequently. Each update can trigger \
    layout calculations. If scroll adjustments happen on every update, performance may suffer. \
    Batching scroll updates helps maintain smooth animation.

    **Paragraph 9: Layout Timing**

    UIKit layout happens asynchronously. When we update text content and immediately try to \
    scroll, the new content height may not be calculated yet. This can cause scrolling to \
    the wrong position or not scrolling far enough.

    **Paragraph 10: The Solution**

    The solution involves periodic layout updates (not on every character), tracking whether \
    the user is "following" at the bottom, and only auto-scrolling when appropriate. This \
    creates a smooth experience that respects user intent.

    **Paragraph 11: Testing Strategy**

    To verify correct behavior, we use UI tests that take screenshots at key moments: \
    initial state, mid-typewriter, before user scroll, after user scroll up, after user \
    scroll down, and completion. These screenshots reveal any scroll issues.

    **Paragraph 12: Conclusion**

    This extra-long response provides ample time to observe all aspects of typewriter scroll \
    behavior. By examining screenshots taken at various stages, we can identify and fix any \
    scrolling issues that may exist in the current implementation.
    """
}

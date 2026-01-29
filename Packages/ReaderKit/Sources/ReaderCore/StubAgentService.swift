import Foundation

/// Stub agent service for UI testing with preset response modes
public actor StubAgentService: AgentServiceProtocol {
    /// Response mode for the stub
    public enum Mode: String {
        case short // Quick verification
        case long // Scroll testing - multiple paragraphs
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
}

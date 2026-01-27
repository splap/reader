import XCTest
@testable import ReaderCore

final class ExecutionGuardrailsTests: XCTestCase {
    func testToolBudgetTracksCallsAndEvidence() {
        var budget = ExecutionGuardrails.ToolBudget()

        XCTAssertTrue(budget.canMakeToolCall)
        XCTAssertFalse(budget.hasEvidence)

        for _ in 0..<ExecutionGuardrails.maxToolCalls {
            XCTAssertTrue(budget.useToolCall())
        }

        XCTAssertFalse(budget.useToolCall())
        XCTAssertFalse(budget.canMakeToolCall)

        budget.recordEvidence(count: 1)
        XCTAssertTrue(budget.hasEvidence)
    }
}

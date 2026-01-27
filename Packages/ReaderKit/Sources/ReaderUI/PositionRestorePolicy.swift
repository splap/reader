import Foundation

struct PositionRestorePolicy {
    /// Determine if webview should be hidden until position is restored
    static func shouldHideUntilRestore(initialCFI: String?) -> Bool {
        initialCFI != nil
    }
}

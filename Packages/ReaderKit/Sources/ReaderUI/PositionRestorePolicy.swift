import Foundation

enum PositionRestorePolicy {
    /// Determine if webview should be hidden until position is restored.
    /// Hides when restoring a saved CFI (initial load), a pending CFI (font resize reload),
    /// or a pending page (scrubber cross-spine navigation).
    static func shouldHideUntilRestore(initialCFI: String?, pendingCFI: Bool = false, pendingPage: Bool = false) -> Bool {
        initialCFI != nil || pendingCFI || pendingPage
    }
}

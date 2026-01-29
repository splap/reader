import Foundation

enum PositionRestorePolicy {
    /// Determine if webview should be hidden until position is restored.
    /// Hides when restoring a saved CFI (initial load) or a pending CFI (font resize reload).
    static func shouldHideUntilRestore(initialCFI: String?, pendingCFI: Bool = false) -> Bool {
        initialCFI != nil || pendingCFI
    }
}

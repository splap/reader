import Foundation
import UIKit

/// Centralized manager for font scale settings across the app
/// Persists to UserDefaults and notifies observers when scale changes
public final class FontScaleManager {
    public static let shared = FontScaleManager()

    private static let fontScaleKey = "ReaderFontScale"
    private static let defaultFontScale: CGFloat = 1.4 // Must be one of the discrete steps

    /// Notification posted when font scale changes
    /// The notification object is the new CGFloat scale value
    public static let fontScaleDidChangeNotification = Notification.Name("FontScaleDidChange")

    /// The current font scale (1.0 to 1.8)
    public var fontScale: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: Self.fontScaleKey)
            return stored > 0 ? CGFloat(stored) : Self.defaultFontScale
        }
        set {
            let clamped = max(1.0, min(1.8, newValue))
            UserDefaults.standard.set(Double(clamped), forKey: Self.fontScaleKey)
            NotificationCenter.default.post(
                name: Self.fontScaleDidChangeNotification,
                object: clamped
            )
        }
    }

    /// Base font size for body text (e.g., 16pt)
    public let baseFontSize: CGFloat = 16

    /// Returns a scaled font size based on the current scale
    /// - Parameter baseSize: The base font size to scale
    /// - Returns: The scaled font size
    public func scaledSize(_ baseSize: CGFloat) -> CGFloat {
        baseSize * fontScale
    }

    /// Returns a UIFont scaled appropriately for body text
    public var bodyFont: UIFont {
        .systemFont(ofSize: scaledSize(baseFontSize))
    }

    /// Returns a UIFont scaled appropriately for secondary/caption text
    public var captionFont: UIFont {
        .systemFont(ofSize: scaledSize(13))
    }

    /// Returns a UIFont scaled appropriately for small text
    public var smallFont: UIFont {
        .systemFont(ofSize: scaledSize(12))
    }

    /// Returns a UIFont scaled appropriately for titles
    public var titleFont: UIFont {
        .systemFont(ofSize: scaledSize(17), weight: .semibold)
    }

    /// Returns a UIFont scaled appropriately for large titles
    public var largeTitleFont: UIFont {
        .systemFont(ofSize: scaledSize(20), weight: .bold)
    }

    /// Returns a scaled monospaced font
    public func monospacedFont(size baseSize: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: scaledSize(baseSize), weight: weight)
    }

    /// Returns a scaled system font with custom weight
    public func scaledFont(size baseSize: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: scaledSize(baseSize), weight: weight)
    }

    private init() {}
}

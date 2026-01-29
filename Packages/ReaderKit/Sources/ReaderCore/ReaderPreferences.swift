import Foundation
import UIKit

/// Rendering mode for book content
public enum RenderMode: String, Codable, CaseIterable {
    case native
    case webView = "webview"

    public var displayName: String {
        switch self {
        case .native: "Native"
        case .webView: "HTML"
        }
    }
}

/// Appearance mode for the reader
public enum AppearanceMode: Int, CaseIterable {
    case dark = 0
    case light = 1
    case system = 2

    public var displayName: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }

    public var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: .unspecified
        }
    }
}

/// Central settings manager for reader preferences
public final class ReaderPreferences {
    public static let shared = ReaderPreferences()

    // MARK: - Notifications

    public static let renderModeDidChangeNotification = Notification.Name("ReaderPreferences.renderModeDidChange")
    public static let appearanceModeDidChangeNotification = Notification.Name("ReaderPreferences.appearanceModeDidChange")
    public static let marginSizeDidChangeNotification = Notification.Name("ReaderPreferences.marginSizeDidChange")
    public static let readerRenderReadyNotification = Notification.Name("ReaderPreferences.readerRenderReady")

    // MARK: - Keys

    private static let renderModeKey = "ReaderRenderMode"
    private static let appearanceModeKey = "AppearanceMode"
    private static let marginSizeKey = "ReaderMarginSize"

    // MARK: - Properties

    /// Current render mode (native attributed strings or WebView HTML)
    public var renderMode: RenderMode {
        get {
            guard let stored = UserDefaults.standard.string(forKey: Self.renderModeKey),
                  let mode = RenderMode(rawValue: stored)
            else {
                return .webView // Default to HTML
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.renderModeKey)
            NotificationCenter.default.post(name: Self.renderModeDidChangeNotification, object: newValue)
        }
    }

    /// Convenience accessor to FontScaleManager's font scale
    public var fontScale: CGFloat {
        get { FontScaleManager.shared.fontScale }
        set { FontScaleManager.shared.fontScale = newValue }
    }

    /// Current appearance mode (dark, light, or system)
    public var appearanceMode: AppearanceMode {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.appearanceModeKey)
            return AppearanceMode(rawValue: stored) ?? .dark // Default to dark
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.appearanceModeKey)
            applyAppearanceMode(newValue)
            NotificationCenter.default.post(name: Self.appearanceModeDidChangeNotification, object: newValue)
        }
    }

    /// Horizontal margin size in pixels (24-96)
    public var marginSize: CGFloat {
        get {
            let stored = UserDefaults.standard.float(forKey: Self.marginSizeKey)
            return stored > 0 ? CGFloat(stored) : 80 // Default to 80px (matches EPUB.js reference)
        }
        set {
            let clamped = min(96, max(24, newValue))
            UserDefaults.standard.set(Float(clamped), forKey: Self.marginSizeKey)
            NotificationCenter.default.post(name: Self.marginSizeDidChangeNotification, object: clamped)
        }
    }

    /// Apply the appearance mode to all windows
    public func applyAppearanceMode(_ mode: AppearanceMode) {
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        window.overrideUserInterfaceStyle = mode.userInterfaceStyle
                    }
                }
            }
        }
    }

    /// Apply current appearance mode on app launch
    public func applyCurrentAppearance() {
        applyAppearanceMode(appearanceMode)
    }

    private init() {}
}

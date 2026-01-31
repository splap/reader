import UIKit

/// Button for use in the unified navigation bar
/// Supports icon-based and text-based variants with consistent styling
final class NavigationBarButton: UIButton {
    /// Create an icon-based button with a system image
    init(systemImage: String) {
        super.init(frame: .zero)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemImage)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        config.baseForegroundColor = Self.adaptiveIconColor
        configuration = config

        setupCommon()
    }

    /// Create a text-based button
    init(title: String, weight: UIFont.Weight = .semibold) {
        super.init(frame: .zero)

        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 17, weight: weight),
        ]))
        config.baseForegroundColor = .systemBlue
        config.contentInsets = .zero
        configuration = config

        setupCommon()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCommon() {
        translatesAutoresizingMaskIntoConstraints = false
    }

    /// Update the button's icon
    func updateIcon(_ systemImage: String) {
        guard var config = configuration else { return }
        config.image = UIImage(systemName: systemImage)
        configuration = config
    }

    /// Update the button's title
    func updateTitle(_ title: String) {
        guard var config = configuration else { return }
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]))
        configuration = config
    }

    /// Adaptive icon color - dark in light mode, light in dark mode
    private static var adaptiveIconColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
    }
}

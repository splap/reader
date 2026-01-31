import UIKit

/// Configuration for the navigation bar content
struct NavigationBarConfiguration {
    let leadingItems: [NavigationBarItem]
    let title: String
    let trailingItems: [NavigationBarItem]

    static let empty = NavigationBarConfiguration(leadingItems: [], title: "", trailingItems: [])
}

/// Items that can be displayed in the navigation bar
enum NavigationBarItem {
    case button(systemImage: String, accessibilityLabel: String, action: () -> Void)
    case textButton(title: String, action: () -> Void)
    case menu(systemImage: String, accessibilityLabel: String, accessibilityIdentifier: String?, menu: UIMenu)
}

/// Protocol for view controllers that provide navigation bar configuration
protocol ReaderNavigationBarProvider: AnyObject {
    /// Return the current bar configuration
    func navigationBarConfiguration() -> NavigationBarConfiguration

    /// Called when the navigation bar visibility changes (reader toggle)
    func navigationBarVisibilityDidChange(_ visible: Bool)
}

/// Unified navigation bar component with blur background
/// Stays fixed while content transitions beneath it
final class ReaderNavigationBar: UIView {
    private let blurView: UIVisualEffectView
    private let leadingStack = UIStackView()
    private let trailingStack = UIStackView()
    private let titleLabel = UILabel()

    /// Bar height constant
    static let height: CGFloat = 56

    override init(frame: CGRect) {
        // Create blur background
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        blurView = UIVisualEffectView(effect: blurEffect)

        super.init(frame: frame)

        setupView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = .clear

        // Blur background
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        addSubview(blurView)

        // Shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4

        // Leading stack (left buttons)
        leadingStack.translatesAutoresizingMaskIntoConstraints = false
        leadingStack.axis = .horizontal
        leadingStack.spacing = 8
        leadingStack.alignment = .center
        addSubview(leadingStack)

        // Trailing stack (right buttons)
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.axis = .horizontal
        trailingStack.spacing = 12
        trailingStack.alignment = .center
        addSubview(trailingStack)

        // Title label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            // Blur fills entire bar
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Leading stack
            leadingStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            leadingStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Trailing stack
            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Title centered, but respects button spacing
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingStack.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -12),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    /// Configure the bar with new content
    /// - Parameters:
    ///   - configuration: The bar configuration
    ///   - animated: Whether to animate the transition
    func configure(with configuration: NavigationBarConfiguration, animated: Bool) {
        let updateBlock = {
            self.titleLabel.text = configuration.title

            // Clear and rebuild leading items
            self.leadingStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for item in configuration.leadingItems {
                let button = self.createButton(for: item)
                self.leadingStack.addArrangedSubview(button)
            }

            // Clear and rebuild trailing items
            self.trailingStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for item in configuration.trailingItems {
                let button = self.createButton(for: item)
                self.trailingStack.addArrangedSubview(button)
            }
        }

        if animated {
            // Cross-fade animation
            UIView.transition(with: self, duration: 0.25, options: .transitionCrossDissolve) {
                updateBlock()
            }
        } else {
            updateBlock()
        }
    }

    private func createButton(for item: NavigationBarItem) -> UIButton {
        switch item {
        case let .button(systemImage, accessibilityLabel, action):
            let button = NavigationBarButton(systemImage: systemImage)
            button.accessibilityLabel = accessibilityLabel
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 44),
                button.heightAnchor.constraint(equalToConstant: 44),
            ])
            return button

        case let .textButton(title, action):
            let button = NavigationBarButton(title: title)
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return button

        case let .menu(systemImage, accessibilityLabel, accessibilityIdentifier, menu):
            let button = NavigationBarButton(systemImage: systemImage)
            button.accessibilityLabel = accessibilityLabel
            button.accessibilityIdentifier = accessibilityIdentifier
            button.showsMenuAsPrimaryAction = true
            button.menu = menu
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 44),
                button.heightAnchor.constraint(equalToConstant: 44),
            ])
            return button
        }
    }
}

import UIKit
import ReaderCore

/// A full-screen overlay view that shows indexing progress with a spinner and status message
final class IndexingProgressView: UIView {
    private let containerView = UIView()
    private let blurView: UIVisualEffectView
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let progressStack = UIStackView()

    override init(frame: CGRect) {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Full-screen semi-transparent background
        backgroundColor = UIColor.black.withAlphaComponent(0.3)

        // Blur container
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 20
        blurView.clipsToBounds = true
        addSubview(blurView)

        // Container for content
        containerView.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(containerView)

        // Activity indicator
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = false
        activityIndicator.startAnimating()
        containerView.addSubview(activityIndicator)

        // Title label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Preparing Book"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        containerView.addSubview(titleLabel)

        // Message label
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = "Building search index..."
        messageLabel.font = .systemFont(ofSize: 14, weight: .regular)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        containerView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            // Blur container centered
            blurView.centerXAnchor.constraint(equalTo: centerXAnchor),
            blurView.centerYAnchor.constraint(equalTo: centerYAnchor),
            blurView.widthAnchor.constraint(equalToConstant: 280),

            // Content container fills blur view
            containerView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 32),
            containerView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 24),
            containerView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -24),
            containerView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -32),

            // Activity indicator at top
            activityIndicator.topAnchor.constraint(equalTo: containerView.topAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            // Title below indicator
            titleLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Message below title
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
    }

    /// Updates the progress display
    /// - Parameter progress: The current indexing progress
    func update(progress: BookLibraryService.IndexingProgress) {
        titleLabel.text = progress.stage.rawValue
        messageLabel.text = progress.message

        // Update indicator state based on stage
        switch progress.stage {
        case .complete:
            activityIndicator.stopAnimating()
        case .failed:
            activityIndicator.stopAnimating()
        default:
            if !activityIndicator.isAnimating {
                activityIndicator.startAnimating()
            }
        }
    }

    /// Shows the view with a fade-in animation
    func show(in parentView: UIView) {
        frame = parentView.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        alpha = 0
        parentView.addSubview(self)

        UIView.animate(withDuration: 0.25) {
            self.alpha = 1
        }
    }

    /// Hides the view with a fade-out animation and removes from superview
    func hide(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
            completion?()
        })
    }
}

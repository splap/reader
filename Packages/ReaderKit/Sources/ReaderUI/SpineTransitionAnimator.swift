import OSLog
import ReaderCore
import UIKit

/// Direction of a spine transition animation.
public enum SpineTransitionDirection {
    case forward // swipe left  -> content slides left
    case backward // swipe right -> content slides right
}

/// Animates spine transitions as a contiguous slide, making them look
/// identical to within-spine page turns: both the outgoing and incoming
/// pages slide together as a continuous strip, edges always touching.
///
/// The animation starts immediately from the gesture — content loads in
/// parallel behind the sliding snapshot. If content is ready before the
/// slide finishes, the WebView is revealed naturally. If not, the snapshot
/// holds at the destination until content arrives.
public final class SpineTransitionAnimator {
    private static let logger = Log.logger(category: "spine-anim")

    /// Prevents double-transitions while an animation is in flight.
    public private(set) var isAnimating = false

    /// Standard animation duration (seconds).
    private var animationDuration: TimeInterval = 0.3

    /// Check for slow-animation launch argument (for UI testing).
    public func configureForTesting(arguments: [String]) {
        if arguments.contains("--uitesting-slow-animations") {
            animationDuration = 2.0
            Self.logger.info("Slow animations enabled for UI testing (2.0s)")
        }
    }

    /// Animate a spine transition.
    ///
    /// The slide starts immediately. Content loads in parallel:
    /// 1. Snapshot current page, place on top of WebView.
    /// 2. Start sliding the snapshot out immediately.
    /// 3. Kick off content load in parallel.
    /// 4. When content is ready AND slide is done, reveal WebView and clean up.
    ///    If content arrives before slide ends, it waits. If slide ends before
    ///    content, the snapshot holds until content is ready.
    public func animate(
        webView: UIView,
        direction: SpineTransitionDirection,
        pageWidth: CGFloat,
        loadNewContent: @escaping (_ contentReady: @escaping () -> Void) -> Void
    ) {
        guard !isAnimating else {
            Self.logger.debug("Ignoring transition — animation already in flight")
            return
        }
        isAnimating = true

        // 1. Snapshot the current page
        let snapshot = webView.snapshotView(afterScreenUpdates: false) ?? UIView()
        snapshot.frame = webView.frame
        webView.superview?.insertSubview(snapshot, aboveSubview: webView)

        // Hide WebView while loading (snapshot covers it)
        webView.alpha = 0

        Self.logger.info("Transition \(direction == .forward ? "forward" : "backward"): slide starting immediately")

        // Track both async completions
        var slideFinished = false
        var contentLoaded = false

        let finishIfBothReady: () -> Void = { [weak self, weak webView] in
            guard slideFinished, contentLoaded else { return }
            guard let self, let webView else {
                snapshot.removeFromSuperview()
                self?.isAnimating = false
                return
            }

            // Both done — reveal the WebView, remove snapshot
            webView.transform = .identity
            webView.alpha = 1
            snapshot.removeFromSuperview()
            isAnimating = false
            Self.logger.info("Transition: complete")
        }

        // 2. Start sliding the snapshot out immediately
        let outgoingX: CGFloat = direction == .forward ? -pageWidth : pageWidth

        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                snapshot.transform = CGAffineTransform(translationX: outgoingX, y: 0)
            },
            completion: { _ in
                slideFinished = true
                finishIfBothReady()
            }
        )

        // 3. Load content in parallel
        loadNewContent {
            contentLoaded = true
            finishIfBothReady()
        }
    }
}

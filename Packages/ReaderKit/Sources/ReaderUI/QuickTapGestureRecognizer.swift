import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A tap gesture that only recognizes if the touch duration is less than the system's
/// standard long press threshold. This prevents tap recognition during text selection
/// without using arbitrary magic numbers.
final class QuickTapGestureRecognizer: UIGestureRecognizer {
    /// Uses the system's default long press duration as the threshold.
    /// Taps held longer than this are considered long presses, not taps.
    private let maximumDuration: TimeInterval = UILongPressGestureRecognizer().minimumPressDuration

    private var touchStartTime: Date?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        guard touches.count == 1 else {
            state = .failed
            return
        }
        touchStartTime = Date()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        // Allow small movement (like standard tap gesture)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)

        guard let startTime = touchStartTime else {
            state = .failed
            return
        }

        let duration = Date().timeIntervalSince(startTime)
        state = duration < maximumDuration ? .recognized : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }

    override func reset() {
        super.reset()
        touchStartTime = nil
    }
}

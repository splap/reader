import XCTest

/// Memory stress tests designed to expose memory leaks, use-after-free, and observer cleanup issues.
/// Run with Address Sanitizer or Thread Sanitizer enabled for best results:
///   ./scripts/test --sanitizer=asan ui:testRapidBookOpenClose
///
/// These tests perform repetitive operations that would cause crashes if:
/// - NotificationCenter observers aren't cleaned up in deinit
/// - Gesture recognizers aren't properly removed
/// - Completion handlers fire after deallocation
final class MemoryStressUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = launchReaderApp()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Stress Tests

    /// Rapidly open and close books to stress notification observers.
    /// If observers aren't cleaned up in deinit, they accumulate and crash when fired.
    func testRapidBookOpenClose() {
        let iterations = 20

        for i in 1 ... iterations {
            // Open book - with extra time for sanitizer overhead
            guard let _ = openBook(in: app, named: "Frankenstein") else {
                print("[\(i)/\(iterations)] Book failed to open, retrying...")
                sleep(2)
                navigateToLibrary(in: app)
                sleep(1)
                continue
            }
            sleep(2)

            // Close book
            navigateToLibrary(in: app)
            sleep(2)

            print("[\(i)/\(iterations)] Open/close cycle complete")
        }

        // If we get here without crashing, observers are being cleaned up
        print("SUCCESS: Completed open/close cycles without crash")
    }

    /// Rapid page navigation to stress gesture recognizers and JS callbacks.
    func testRapidPageNavigation() {
        let webView = openFrankenstein(in: app)

        // Swipe forward rapidly
        for i in 1 ... 30 {
            webView.swipeLeft()
            usleep(300_000) // 300ms - slower for sanitizer overhead
            if i % 10 == 0 {
                print("Swipe forward \(i)/30")
            }
        }

        // Swipe backward rapidly
        for i in 1 ... 30 {
            webView.swipeRight()
            usleep(300_000)
            if i % 10 == 0 {
                print("Swipe backward \(i)/30")
            }
        }

        print("SUCCESS: Completed 60 rapid page navigations without crash")
    }

    /// Jump around chapters via TOC to stress chapter loading/unloading.
    func testRapidChapterJumping() {
        let webView = openFrankenstein(in: app)

        let chapters = ["letter 1", "letter 2", "letter 3", "letter 4", "chapter 1", "chapter 2"]

        for i in 1 ... 20 {
            let chapter = chapters[i % chapters.count]

            // Navigate to chapter via TOC
            let success = navigateToTOCEntry(in: app, webView: webView, matching: chapter)
            if success {
                print("[\(i)/20] Jumped to '\(chapter)'")
            } else {
                print("[\(i)/20] Could not find '\(chapter)', continuing")
            }
            sleep(2)
        }

        print("SUCCESS: Completed chapter jumping stress test without crash")
    }

    /// Combined stress: open book, navigate, change settings, close, repeat.
    /// This exercises multiple observer patterns in quick succession.
    func testCombinedStress() {
        for i in 1 ... 10 {
            // Open book
            guard let webView = openBook(in: app, named: "Frankenstein") else {
                print("[\(i)/10] Failed to open book, skipping")
                sleep(2)
                navigateToLibrary(in: app)
                sleep(1)
                continue
            }

            // Navigate a few pages
            for _ in 1 ... 3 {
                webView.swipeLeft()
                usleep(400_000)
            }

            // Sometimes change font size
            if i % 3 == 0 {
                webView.tap()
                sleep(1)

                let settingsButton = app.buttons["Settings"]
                if settingsButton.waitForExistence(timeout: 3), settingsButton.isHittable {
                    settingsButton.tap()

                    let slider = app.sliders.firstMatch
                    if slider.waitForExistence(timeout: 3) {
                        let size = CGFloat.random(in: 0.3 ... 0.8)
                        slider.adjust(toNormalizedSliderPosition: size)
                        sleep(2)
                    }

                    let doneButton = app.navigationBars.buttons.firstMatch
                    if doneButton.exists {
                        doneButton.tap()
                    }
                    sleep(2)
                }
            }

            // Sometimes jump to a different chapter
            if i % 4 == 0 {
                let chapters = ["letter 2", "chapter 1", "chapter 3"]
                let chapter = chapters.randomElement()!
                _ = navigateToTOCEntry(in: app, webView: webView, matching: chapter)
                sleep(3)
            }

            // Close book
            navigateToLibrary(in: app)
            sleep(2)

            print("[\(i)/10] Combined stress cycle complete")
        }

        print("SUCCESS: Completed combined stress test without crash")
    }

    /// Holds the app open for external leak detection.
    /// Run this test, then use `./scripts/check-leaks` in another terminal.
    func testHoldForLeakDetection() {
        // Exercise the app first to create potential leaks
        for i in 1 ... 5 {
            _ = openFrankenstein(in: app)
            sleep(1)

            // Navigate around
            let webView = getReaderView(in: app)
            for _ in 1 ... 10 {
                webView.swipeLeft()
                usleep(200_000)
            }

            navigateToLibrary(in: app)
            sleep(1)
            print("[\(i)/5] Exercise cycle complete")
        }

        print("")
        print("=== APP READY FOR LEAK DETECTION ===")
        print("In another terminal, run: ./scripts/check-leaks -v")
        print("Holding for 60 seconds...")
        print("")

        // Hold app open for leak detection
        sleep(60)

        print("Leak detection window closed")
    }

    // MARK: - Aggressive Stress Tests

    /// Very aggressive open/close cycling with minimal delays.
    /// This is more likely to trigger race conditions.
    func testAggressiveOpenClose() {
        let iterations = 25

        for i in 1 ... iterations {
            guard let _ = openBook(in: app, named: "Frankenstein") else {
                print("[\(i)/\(iterations)] Book failed to open, continuing")
                sleep(1)
                navigateToLibrary(in: app)
                sleep(1)
                continue
            }
            sleep(1)

            navigateToLibrary(in: app)
            sleep(1)

            if i % 5 == 0 {
                print("[\(i)/\(iterations)] Aggressive open/close cycle")
            }
        }

        print("SUCCESS: Completed aggressive open/close cycles")
    }

    /// Stress test that alternates between two different books.
    func testMultipleBookStress() {
        let books = ["Frankenstein", "Meditations"]

        for i in 1 ... 12 {
            let book = books[i % 2]

            guard let webView = openBook(in: app, named: book) else {
                print("Could not open \(book), skipping")
                sleep(1)
                navigateToLibrary(in: app)
                sleep(1)
                continue
            }

            // Quick navigation
            for _ in 1 ... 3 {
                webView.swipeLeft()
                usleep(400_000)
            }

            navigateToLibrary(in: app)
            sleep(2)

            print("[\(i)/12] Opened and closed \(book)")
        }

        print("SUCCESS: Completed multi-book stress test")
    }

    /// Stress test the scrubber slider by rapidly adjusting position.
    func testRapidScrubberAdjustment() {
        let webView = openFrankenstein(in: app)

        // Navigate to a chapter with many pages
        _ = navigateToTOCEntry(in: app, webView: webView, matching: "chapter 1")
        sleep(2)

        for i in 1 ... 20 {
            // Tap to reveal overlay
            webView.tap()
            sleep(1)

            let scrubber = app.sliders["Page scrubber"]
            guard scrubber.waitForExistence(timeout: 3) else {
                print("Scrubber not found on iteration \(i)")
                continue
            }

            // Rapidly adjust position
            let positions: [CGFloat] = [0.0, 0.5, 1.0, 0.25, 0.75]
            for pos in positions {
                scrubber.adjust(toNormalizedSliderPosition: pos)
                usleep(100_000) // 100ms
            }

            // Dismiss overlay
            webView.tap()
            sleep(1)

            print("[\(i)/20] Scrubber stress cycle complete")
        }

        print("SUCCESS: Completed scrubber stress test")
    }
}

import SwiftUI
import UIKit
import XCTest

enum SnapshotTestHelper {
    @MainActor
    static func assertSnapshot<V: View>(
        _ view: V,
        size: CGSize,
        name: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.bounds = CGRect(origin: .zero, size: size)
        hostingController.view.backgroundColor = .white
        hostingController.overrideUserInterfaceStyle = .light
        hostingController.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            hostingController.view.layer.render(in: context.cgContext)
        }

        guard let data = image.pngData() else {
            XCTFail("Failed to encode snapshot image", file: file, line: line)
            return
        }

        let snapshotDirectory = snapshotDirectoryURL(filePath: file)
        let snapshotName = sanitizedSnapshotName(name ?? testName)
        let snapshotURL = snapshotDirectory.appendingPathComponent(snapshotName).appendingPathExtension("png")

        let shouldRecord: Bool
#if SNAPSHOT_RECORD
        shouldRecord = true
#else
        shouldRecord = ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] == "1"
#endif

        if shouldRecord {
            do {
                try FileManager.default.createDirectory(
                    at: snapshotDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try data.write(to: snapshotURL, options: .atomic)
            } catch {
                XCTFail("Failed to write snapshot: \(error)", file: file, line: line)
            }
            return
        }

        guard let baselineData = try? Data(contentsOf: snapshotURL) else {
            XCTFail("Missing snapshot: \(snapshotURL.path). Run UPDATE_SNAPSHOTS=1 to record.", file: file, line: line)
            return
        }

        guard data == baselineData else {
            let attachment = XCTAttachment(image: image)
            attachment.name = "Snapshot"
            attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "Snapshot mismatch") { activity in
                activity.add(attachment)
            }
            XCTFail("Snapshot mismatch for \(snapshotName)", file: file, line: line)
            return
        }
    }

    private static func snapshotDirectoryURL(filePath: StaticString) -> URL {
        let fileURL = URL(fileURLWithPath: String(describing: filePath))
        return fileURL.deletingLastPathComponent().appendingPathComponent("__Snapshots__")
    }

    private static func sanitizedSnapshotName(_ name: String) -> String {
        var cleaned = name
        if cleaned.hasPrefix("test") {
            cleaned.removeFirst("test".count)
        }
        if cleaned.hasSuffix("()") {
            cleaned.removeLast(2)
        }
        return cleaned.isEmpty ? "Snapshot" : cleaned
    }
}

import Foundation
import OSLog
import ReaderCore
import WebKit

/// Custom URL scheme handler that serves EPUB images from an in-memory cache
/// This avoids embedding images as base64 in HTML, which causes massive performance issues
public final class EPUBURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let logger = Log.logger(category: "url-scheme")

    /// The custom URL scheme used for EPUB resources
    public static let scheme = "epub-resource"

    /// Cache of image data keyed by path
    private var imageCache: [String: Data] = [:]

    /// Initialize with image cache from EPUB
    public init(imageCache: [String: Data]) {
        self.imageCache = imageCache
        super.init()
    }

    /// Update the image cache (e.g., when switching books)
    public func updateCache(_ imageCache: [String: Data]) {
        self.imageCache = imageCache
    }

    public func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // Extract the image path from the URL
        // URL format: epub-resource://image/path/to/image.jpg
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path

        // Try to find the image in cache
        if let imageData = findImage(path: path) {
            let mimeType = mimeType(for: path)
            let response = URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: imageData.count,
                textEncodingName: nil
            )

            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(imageData)
            urlSchemeTask.didFinish()
        } else {
            Self.logger.warning("Image not found in cache: \(path)")
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    public func webView(_: WKWebView, stop _: any WKURLSchemeTask) {
        // Nothing to clean up for synchronous requests
    }

    /// Find image data by trying various path variations
    private func findImage(path: String) -> Data? {
        // Try exact path
        if let data = imageCache[path] {
            return data
        }

        // Try just the filename
        let filename = (path as NSString).lastPathComponent
        if let data = imageCache[filename] {
            return data
        }

        // Try without leading directories
        for (cachedPath, data) in imageCache {
            if cachedPath.hasSuffix(path) || path.hasSuffix(cachedPath) {
                return data
            }
            let cachedFilename = (cachedPath as NSString).lastPathComponent
            if cachedFilename == filename {
                return data
            }
        }

        return nil
    }

    /// Get MIME type for image file
    private func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }
}

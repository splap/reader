import OSLog

public enum Log {
    public static let subsystem = "com.splap.reader"

    public static func logger(category: String) -> DebugLogger {
        DebugLogger(category: category)
    }
}

/// Logger wrapper that shows full values in DEBUG builds, respects privacy in release
public struct DebugLogger {
    private let logger: Logger

    init(category: String) {
        self.logger = Logger(subsystem: Log.subsystem, category: category)
    }

    public func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #else
        logger.debug("\(message)")
        #endif
    }

    public func info(_ message: String) {
        #if DEBUG
        logger.info("\(message, privacy: .public)")
        #else
        logger.info("\(message)")
        #endif
    }

    public func warning(_ message: String) {
        #if DEBUG
        logger.warning("\(message, privacy: .public)")
        #else
        logger.warning("\(message)")
        #endif
    }

    public func error(_ message: String) {
        #if DEBUG
        logger.error("\(message, privacy: .public)")
        #else
        logger.error("\(message)")
        #endif
    }
}

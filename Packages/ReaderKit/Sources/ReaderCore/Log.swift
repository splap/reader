import OSLog

public enum Log {
    public static let subsystem = "com.splap.reader"

    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}

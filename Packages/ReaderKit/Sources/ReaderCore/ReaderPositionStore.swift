import Foundation

// MARK: - Legacy Position Storage (Page-Based)

public protocol ReaderPositionStoring {
    func load(chapterId: String) -> ReaderPosition?
    func save(_ position: ReaderPosition)
}

public final class UserDefaultsPositionStore: ReaderPositionStoring {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(chapterId: String) -> ReaderPosition? {
        let key = keyForChapter(chapterId)
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredPosition.self, from: data)
        else {
            return nil
        }

        return ReaderPosition(
            chapterId: stored.chapterId,
            pageIndex: stored.pageIndex,
            characterOffset: stored.characterOffset,
            maxReadPageIndex: stored.maxReadPageIndex ?? stored.pageIndex
        )
    }

    public func save(_ position: ReaderPosition) {
        let stored = StoredPosition(
            chapterId: position.chapterId,
            pageIndex: position.pageIndex,
            characterOffset: position.characterOffset,
            maxReadPageIndex: position.maxReadPageIndex
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: keyForChapter(position.chapterId))
    }

    private func keyForChapter(_ chapterId: String) -> String {
        "reader.position.\(chapterId)"
    }

    private struct StoredPosition: Codable {
        let chapterId: String
        let pageIndex: Int
        let characterOffset: Int
        let maxReadPageIndex: Int?  // Optional for backwards compatibility
    }
}

// MARK: - Block-Based Position Storage

public protocol BlockPositionStoring {
    func load(bookId: String) -> BlockPosition?
    func save(_ position: BlockPosition)
}

public final class UserDefaultsBlockPositionStore: BlockPositionStoring {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(bookId: String) -> BlockPosition? {
        let key = keyForBook(bookId)
        guard let data = defaults.data(forKey: key),
              let position = try? JSONDecoder().decode(BlockPosition.self, from: data)
        else {
            return nil
        }
        return position
    }

    public func save(_ position: BlockPosition) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        defaults.set(data, forKey: keyForBook(position.bookId))
    }

    private func keyForBook(_ bookId: String) -> String {
        "reader.block.position.\(bookId)"
    }
}

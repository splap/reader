import Foundation

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
            characterOffset: stored.characterOffset
        )
    }

    public func save(_ position: ReaderPosition) {
        let stored = StoredPosition(
            chapterId: position.chapterId,
            pageIndex: position.pageIndex,
            characterOffset: position.characterOffset
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
    }
}

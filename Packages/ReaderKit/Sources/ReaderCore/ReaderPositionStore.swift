import Foundation

// MARK: - CFI Position Storage

public protocol CFIPositionStoring {
    func load(bookId: String) -> CFIPosition?
    func save(_ position: CFIPosition)
}

public final class UserDefaultsCFIPositionStore: CFIPositionStoring {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(bookId: String) -> CFIPosition? {
        let key = keyForBook(bookId)
        guard let data = defaults.data(forKey: key),
              let position = try? JSONDecoder().decode(CFIPosition.self, from: data)
        else {
            return nil
        }
        return position
    }

    public func save(_ position: CFIPosition) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        defaults.set(data, forKey: keyForBook(position.bookId))
    }

    private func keyForBook(_ bookId: String) -> String {
        "reader.cfi.position.\(bookId)"
    }
}

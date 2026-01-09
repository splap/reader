public struct ReaderPosition: Equatable {
    public let chapterId: String
    public let pageIndex: Int
    public let characterOffset: Int
    public let maxReadPageIndex: Int  // Furthest page user has reached

    public init(chapterId: String, pageIndex: Int, characterOffset: Int, maxReadPageIndex: Int? = nil) {
        self.chapterId = chapterId
        self.pageIndex = pageIndex
        self.characterOffset = characterOffset
        self.maxReadPageIndex = maxReadPageIndex ?? pageIndex
    }
}

public struct ReaderPosition: Equatable {
    public let chapterId: String
    public let pageIndex: Int
    public let characterOffset: Int

    public init(chapterId: String, pageIndex: Int, characterOffset: Int) {
        self.chapterId = chapterId
        self.pageIndex = pageIndex
        self.characterOffset = characterOffset
    }
}

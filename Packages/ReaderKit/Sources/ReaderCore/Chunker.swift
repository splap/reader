import Foundation

/// Chunks blocks into ~800 token groups with 10% overlap
public struct Chunker {
    /// Target tokens per chunk
    public static let targetTokens = 800

    /// Overlap percentage (10%)
    public static let overlapPercent = 0.10

    /// Chunks a list of blocks into token-based chunks
    /// - Parameters:
    ///   - blocks: The blocks to chunk (should be from a single chapter)
    ///   - bookId: The book identifier
    ///   - chapterId: The chapter/spine item identifier
    /// - Returns: Array of chunks with ~800 tokens each and 10% overlap
    public static func chunk(blocks: [Block], bookId: String, chapterId: String) -> [Chunk] {
        guard !blocks.isEmpty else { return [] }

        var chunks: [Chunk] = []
        var currentBlocks: [Block] = []
        var currentTokens = 0
        var currentStartOffset = 0
        var chunkOrdinal = 0

        // Track character offsets
        var blockStartOffsets: [String: Int] = [:]
        var runningOffset = 0
        for block in blocks {
            blockStartOffsets[block.id] = runningOffset
            runningOffset += block.textContent.count + 1  // +1 for space/newline between blocks
        }

        for block in blocks {
            let blockTokens = Chunk.estimateTokens(block.textContent)

            // If adding this block would exceed target, emit current chunk
            if currentTokens + blockTokens > targetTokens && !currentBlocks.isEmpty {
                let chunk = createChunk(
                    from: currentBlocks,
                    bookId: bookId,
                    chapterId: chapterId,
                    startOffset: currentStartOffset,
                    ordinal: chunkOrdinal,
                    blockStartOffsets: blockStartOffsets
                )
                chunks.append(chunk)
                chunkOrdinal += 1

                // Calculate overlap: keep last 10% of tokens worth of blocks
                let overlapTokens = Int(Double(targetTokens) * overlapPercent)
                var overlapBlocks: [Block] = []
                var overlapTokenCount = 0

                // Walk backwards through current blocks to find overlap
                for b in currentBlocks.reversed() {
                    let bTokens = Chunk.estimateTokens(b.textContent)
                    if overlapTokenCount + bTokens <= overlapTokens {
                        overlapBlocks.insert(b, at: 0)
                        overlapTokenCount += bTokens
                    } else {
                        break
                    }
                }

                currentBlocks = overlapBlocks
                currentTokens = overlapTokenCount
                if let firstOverlapBlock = overlapBlocks.first {
                    currentStartOffset = blockStartOffsets[firstOverlapBlock.id] ?? 0
                }
            }

            // If this is the first block in a new chunk, update start offset
            if currentBlocks.isEmpty {
                currentStartOffset = blockStartOffsets[block.id] ?? 0
            }

            currentBlocks.append(block)
            currentTokens += blockTokens
        }

        // Emit final chunk if there are remaining blocks
        if !currentBlocks.isEmpty {
            let chunk = createChunk(
                from: currentBlocks,
                bookId: bookId,
                chapterId: chapterId,
                startOffset: currentStartOffset,
                ordinal: chunkOrdinal,
                blockStartOffsets: blockStartOffsets
            )
            chunks.append(chunk)
        }

        return chunks
    }

    /// Creates a chunk from a list of blocks
    private static func createChunk(
        from blocks: [Block],
        bookId: String,
        chapterId: String,
        startOffset: Int,
        ordinal: Int,
        blockStartOffsets: [String: Int]
    ) -> Chunk {
        let text = blocks.map { $0.textContent }.joined(separator: "\n")
        let blockIds = blocks.map { $0.id }

        // Calculate end offset
        let lastBlock = blocks.last!
        let lastBlockStart = blockStartOffsets[lastBlock.id] ?? 0
        let endOffset = lastBlockStart + lastBlock.textContent.count

        return Chunk(
            bookId: bookId,
            chapterId: chapterId,
            text: text,
            blockIds: blockIds,
            startOffset: startOffset,
            endOffset: endOffset,
            ordinal: ordinal
        )
    }

    /// Chunks all chapters of a book
    /// - Parameters:
    ///   - chapters: The chapters to chunk
    ///   - bookId: The book identifier
    /// - Returns: All chunks for the book, organized by chapter
    public static func chunkBook(chapters: [Chapter], bookId: String) -> [Chunk] {
        var allChunks: [Chunk] = []

        for chapter in chapters {
            // Collect all blocks from all HTML sections in this chapter
            let blocks = chapter.htmlSections.flatMap { $0.blocks }
            let chapterId = chapter.id

            let chapterChunks = chunk(blocks: blocks, bookId: bookId, chapterId: chapterId)
            allChunks.append(contentsOf: chapterChunks)
        }

        return allChunks
    }
}

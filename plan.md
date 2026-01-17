# Tool-First Book Chat Architecture

## Goal

Answer questions about a book without preloading large context. The model starts with minimal context and retrieves what it needs via tools.

## Preprocessing Infrastructure ✓ COMPLETE

All preprocessing artifacts are built at book import time in `BookLibraryService.indexBookSync()`:

| Artifact | Status | Files |
|----------|--------|-------|
| Chunk Store (FTS5) | ✓ | `Chunk.swift`, `Chunker.swift`, `ChunkStore.swift` |
| Semantic Vector Index | ✓ | `EmbeddingService.swift`, `VectorStore.swift`, `bge-small-en.mlpackage` |
| Book Concept Map | ✓ | `TFIDFAnalyzer.swift`, `EntityExtractor.swift`, `ThemeClusterer.swift`, `ConceptMap.swift`, `ConceptMapStore.swift` |

**Tools implemented** in `AgentTools.swift`:
- `search_content` — FTS5 lexical search
- `semantic_search` — vector similarity search
- `book_concept_map_lookup` — entity/theme/event routing

## Lazy Artifacts ✓ COMPLETE

Generated on-demand and cached:

| Artifact | Status | Files |
|----------|--------|-------|
| Chapter Summaries | ✓ | `ChapterSummaryService.swift` |
| Book Synopsis | ✓ | `BookSynopsisService.swift` |

**Tools implemented** in `AgentTools.swift`:
- `get_chapter_summary` — lazy generation with map-reduce for long chapters
- `get_book_synopsis` — synthesized from chapter summaries + concept map

## Runtime Flow ✓ COMPLETE

### Router (Heuristic + Concept Map)

Implemented in `BookChatRouter.swift`:

**Input:** question, book metadata, concept map
**Output:** `RoutingResult { route: NOT_BOOK | BOOK | AMBIGUOUS, confidence: 0-1, suggestedChapterIds: [...], suggestedQueries: [...] }`

### Execution

Integrated into `ReaderAgentService.swift`:

1. **If AMBIGUOUS:** System prompt suggests using `book_concept_map_lookup` first
2. **If BOOK:**
   - Routing provides suggested chapters from concept map
   - System prompt enforces evidence requirement
   - Tool budget limits retrieval attempts
3. **If NOT_BOOK:** System prompt allows direct knowledge answers

## Guardrails ✓ COMPLETE

Implemented in `BookChatRouter.swift` and `ReaderAgentService.swift`:

- **Tool budget:** max 8 calls per question (enforced in agent loop)
- **Evidence rule:** system prompt requires evidence for book claims
- **Degradation:** graceful fallback when embeddings/concept map unavailable

# Tool-First Book QA Architecture

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

## TODO: Lazy Artifacts

These are generated on-demand and cached:

6. **Chapter Summaries** — map-reduce summarization for long chapters
7. **Book Synopsis** — synthesized from chapter summaries (optional)

**Tools needed:**
- `chapter_summary.get(chapter_id)` — lazy + cached
- `book_synopsis.get()` — lazy + cached

## TODO: Runtime Flow

### Router (LLM, constrained output)

For each user question, decide whether to use book tools:

**Input:** question, book metadata, tool list
**Output:** `{ route: NOT_BOOK | BOOK | AMBIGUOUS, confidence: 0-1, suggested_queries: [...] }`

### Execution

1. **If AMBIGUOUS:** run `book_concept_map_lookup(question)` — strong hits → BOOK, else → NOT_BOOK
2. **If BOOK:**
   - Scope via concept map → candidate `chapter_ids`
   - Retrieve: `text_search` for concrete queries, `semantic_search` for conceptual
   - Escalate scope at most once (chapters → whole book)
   - Optional: `chapter_summary.get()` for narrative context
   - Answer with citations; if insufficient evidence, say so
3. **If NOT_BOOK:** answer normally without book tools

## Guardrails

- **Tool budget:** max 8 calls per question
- **Evidence rule:** no book-specific answers without retrieved evidence
- **Degradation:** if embeddings unavailable, fall back to lexical-only mode

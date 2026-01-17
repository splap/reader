# Reader

A native iPadOS EPUB reader with integrated LLM assistant. Select text in any book and ask questions - the AI can search the book, look up Wikipedia, and display maps inline.

## Demo

Import an EPUB, read with paginated CSS columns, select text and chat:

- Ask "Who is this character?" and the LLM searches the book for mentions
- Ask "Where is this place?" and see an inline map
- Ask general questions and get Wikipedia-augmented answers

## Features

| Feature | Implementation |
|---------|---------------|
| EPUB Rendering | WKWebView with CSS multi-column pagination |
| Text Selection | JavaScript bridge to native selection handling |
| LLM Integration | OpenRouter API with tool-calling agent loop |
| Book Search | FTS5 lexical + semantic vector search |
| Concept Map | Entity/theme routing for scoped retrieval |
| Wikipedia Lookup | Fetch summaries and images inline |
| Map Display | MapKit snapshots rendered in chat |
| Conversation History | Persisted with full execution traces |
| Reading Position | Auto-saved per book |

## Tool-First Book QA

The reader implements a **tool-first QA architecture**: the LLM starts with minimal context and retrieves what it needs via tools, rather than preloading the entire book.

### Preprocessing Pipeline

When a book is imported, `BookLibraryService.indexBookSync()` builds three artifacts:

**1. Chunk Store** — Text split into ~800 token chunks with 10% overlap
- Files: `Chunk.swift`, `Chunker.swift`, `ChunkStore.swift`
- Storage: SQLite with FTS5 virtual table for lexical search
- BM25 ranking, scoped by chapter

**2. Semantic Vector Index** — Dense embeddings for conceptual search
- Model: `BAAI/bge-small-en-v1.5` (384-dim, MIT license)
- Runtime: Core ML with Neural Engine acceleration
- Index: HNSW via USearch (Swift bindings)
- Files: `EmbeddingService.swift`, `VectorStore.swift`
- Conversion: `scripts/convert_bge_to_coreml.py`

**3. Book Concept Map** — Lightweight routing metadata
- Entities: capitalized spans with salience scoring and co-occurrence
- Themes: hierarchical agglomerative clustering (70/30 semantic/TF-IDF blend)
- Events: entity pair interactions with chapter coverage
- Hard caps: ≤500 entities, ≤200 themes, ≤500 events; each links to ≤24 chapters
- Files: `TFIDFAnalyzer.swift`, `EntityExtractor.swift`, `ThemeClusterer.swift`, `ConceptMap.swift`, `ConceptMapStore.swift`

### Agent Tools

Defined in `AgentTools.swift`, executed by `ToolExecutor`:

| Tool | Purpose |
|------|---------|
| `search_content` | FTS5 lexical search with BM25 ranking |
| `semantic_search` | Vector similarity for conceptual queries |
| `book_concept_map_lookup` | Route queries to relevant chapters |
| `get_chapter_text` | Full chapter content |
| `get_surrounding_context` | Blocks around a position |
| `get_character_mentions` | All mentions of an entity |
| `get_book_structure` | Table of contents |
| `wikipedia_lookup` | External knowledge |
| `show_map` | Inline map display |
| `render_image` | Inline image display |

### Runtime Flow

See `plan.md` for the router and execution flow specification. The runtime orchestrates tool calls with:
- Max 8 tool calls per question
- Single scope escalation (chapters → whole book)
- Evidence rule: no book answers without retrieved support

## Architecture

```
Reader/
├── App/                        # Thin app shell
│   └── Resources/
│       └── bge-small-en.mlpackage  # Embedding model (128MB)
├── Packages/ReaderKit/
│   └── Sources/
│       ├── ReaderCore/         # Domain logic (no UIKit)
│       │   ├── EPUBLoader      # EPUB extraction & parsing
│       │   ├── Chunker         # Text chunking for search
│       │   ├── ChunkStore      # FTS5 lexical index
│       │   ├── EmbeddingService    # Core ML embeddings
│       │   ├── VectorStore     # HNSW semantic index
│       │   ├── ConceptMap*     # Entity/theme extraction
│       │   ├── ReaderAgentService  # LLM agent with tool loop
│       │   ├── AgentTools      # Tool definitions
│       │   └── BookContext     # Provides content to tools
│       └── ReaderUI/           # UIKit view controllers
├── scripts/                    # Reproducible build automation
│   └── convert_bge_to_coreml.py  # Model conversion
└── project.yml                 # XcodeGen project definition
```

### Design Decisions

**WKWebView over TextKit**: EPUB content is HTML/CSS. Rather than converting to attributed strings, render natively in a web view with CSS column pagination. Trade-off: text selection requires a JavaScript bridge.

**SPM Package Architecture**: All feature code lives in `ReaderKit` as a Swift Package. The app target is a thin shell. This enables fast incremental builds and clear dependency boundaries.

**On-Device Embeddings**: The 128MB bge-small-en model runs entirely on-device via Core ML, using the Neural Engine when available. No network calls for semantic search.

**Tool-Calling Agent**: The LLM uses a multi-turn tool-calling loop. When the model needs book content, it calls search tools. Results feed back into the conversation until the model produces a final response.

**Execution Traces**: Every LLM response includes a trace of what tools were called, with arguments and results. These traces persist with the conversation for debugging.

## Requirements

- Xcode 15+
- iOS 17.0+ (iPad)
- [Mint](https://github.com/yonaskolb/mint) (for XcodeGen)
- OpenRouter API key

### Model Conversion (one-time)

The embedding model must be converted to Core ML format:

```bash
# Convert model (creates App/Resources/bge-small-en.mlpackage)
uv run --with transformers --with torch --with coremltools python scripts/convert_bge_to_coreml.py
```

## Quick Start

```bash
# Bootstrap (installs deps, generates Xcode project)
./scripts/bootstrap

# Build and run on simulator
./scripts/run &

# Run tests
./scripts/test
```

## Scripts

| Script | Purpose |
|--------|---------|
| `bootstrap` | Install dependencies, generate Xcode project |
| `build` | Deterministic xcodebuild |
| `run` | Build, install, launch, stream logs |
| `test` | Unit tests (`test ui` for UI tests) |
| `lint` | SwiftLint + SwiftFormat |

## Configuration

Set `OpenRouterAPIKey` in app settings. The LLM model can be changed at runtime.

## Development Notes

### Logging

Centralized OSLog with subsystem `com.splap.reader`:

```swift
private static let logger = Log.logger(category: "feature")
Self.logger.info("Event: \(value, privacy: .public)")
```

### Debug Transcript

Tap the doc icon in chat to copy the full LLM transcript - shows exactly what was sent to the model and what came back, including all tool calls.

### AI-Assisted Development

This project uses Claude Code for development. See `AGENTS.md` for the development workflow, including simulator management, logging standards, and deployment verification practices.

# Reader

A native iPadOS EPUB reader with a book-centric chat interface and tool-calling LLM agent. The default renderer is native TextKit pagination (HTML to attributed strings), with an optional HTML WKWebView fallback for fidelity.

## Demo

Import an EPUB, read with paginated pages, select text and send it to chat:

- Use the selection menu "Send to LLM" share-to-chat action to open chat with context
- Ask "Who is this character?" and the agent uses search tools to find mentions
- Ask "Where is this place?" and the agent can call Wikipedia + map tools for context
- Ask general questions and the agent can call Wikipedia when helpful
- Toggle the reader overlay and scrub pages

## Features

| Feature | Implementation |
|---------|---------------|
| EPUB Rendering | Native TextKit pagination (default) + HTML WKWebView fallback |
| Renderer Switching | Reader settings: Native vs HTML |
| Text Selection | Selection menu includes share-to-chat ("Send to LLM") + JS bridge (web) |
| Chat Interface | Full-screen chat anchored to the current book + conversation drawer |
| LLM Integration | OpenRouter API with tool-calling agent loop |
| Book Search | FTS5 lexical + HNSW semantic vector search |
| Concept Map | Entity/theme/event routing for scoped retrieval |
| Summaries | Lazy chapter summaries + book synopsis (cached) |
| Chat Guardrails | Router + tool budget + evidence requirement |
| Map + Images | MapKit snapshots + inline image rendering |
| Conversation History | Persisted with execution traces and transcript copy |
| Reading UI | Tap-to-toggle overlay, page scrubber, max-read extent |
| Reading Position | Page/block position persistence per book |

## Chat Interface

The chat UI is built around the current book:

- **Conversation drawer** to switch or start new chats for the same book
- **Selection-to-chat**: the "Send to LLM" action passes selected text + local context into the chat
- **Debug transcript**: copy full tool traces from the chat toolbar

## Rendering

The reader supports two renderers that share a common `PageRenderer` protocol:

- **Native (default)**: EPUB HTML is converted into attributed strings (`HTMLToAttributedStringConverter`) and paginated with `TextEngine`, which builds isolated text systems per page. Selection uses the system UITextView edit menu with a "Send to LLM" action.
- **HTML (optional)**: A WKWebView renders the original HTML/CSS with column pagination and a JavaScript bridge for selection and position tracking.

Renderer choice is stored in `ReaderPreferences` and can be changed in Reader Settings.

## Tool-First Book Chat

The reader implements a tool-first chat architecture: the LLM starts with minimal context and retrieves what it needs via tools.

### Preprocessing Pipeline

When a book is imported, `BookLibraryService.indexBookSync()` builds these artifacts in the background:

**1. Chunk Store + Lexical Index (FTS5)**
- Text split into ~800 token chunks with ~10% overlap
- SQLite FTS5 index with BM25 ranking and chapter scoping

**2. Semantic Vector Index**
- Embeddings model: `BAAI/bge-small-en-v1.5` (384-dim, Core ML)
- ANN index: HNSW via USearch
- If the embedding model is unavailable, semantic indexing is skipped

**3. Book Concept Map**
- Entities from high-salience capitalized spans and co-occurrence
- Themes from TF-IDF keyword vectors + optional chapter embeddings (70/30 blend)
- Events from entity co-occurrences across chapters
- Hard caps enforced in `ConceptMap`: entities <= 500, themes <= 200, events <= 500

**Indexing status UI:** There is no in-chat progress indicator yet; indexing runs silently in the background.

### Lazy Artifacts

Generated on demand and cached:

- **Chapter summaries** via map-reduce for long chapters
- **Book synopsis** synthesized from summaries and/or concept map

### Agent Tools

Defined in `AgentTools.swift`, executed by `ToolExecutor`:

| Tool | Purpose |
|------|---------|
| `get_current_position` | Current chapter and progress |
| `get_chapter_text` | Full chapter content |
| `search_content` | FTS5 lexical search |
| `semantic_search` | Vector similarity search |
| `book_concept_map_lookup` | Route queries to relevant chapters |
| `get_character_mentions` | All mentions of an entity |
| `get_surrounding_context` | Blocks around a position |
| `get_book_structure` | Table of contents |
| `get_chapter_summary` | Lazy chapter summary |
| `get_book_synopsis` | Lazy book synopsis |
| `wikipedia_lookup` | External knowledge |
| `show_map` | Inline map display |
| `render_image` | Inline image display |

### Runtime Flow

The agent orchestrates tool calls with a routing step and guardrails:

1. **Route question** using a heuristic router and concept map hints.
2. **If ambiguous**, use `book_concept_map_lookup` to decide book vs general.
3. **If book-related**, retrieve evidence with lexical/semantic search and answer with citations.
4. **If general**, answer directly (tools optional).

Guardrails enforced in `ReaderAgentService`:
- Max 8 tool calls per question
- Evidence requirement for book claims
- Lexical-only fallback when semantic index is unavailable

## Architecture

```
Reader/
├── App/                        # Thin app shell
│   └── Resources/
│       └── bge-small-en.mlpackage  # Embedding model
├── Packages/ReaderKit/
│   └── Sources/
│       ├── ReaderCore/         # Domain logic (no UIKit)
│       │   ├── EPUBLoader
│       │   ├── HTMLToAttributedString
│       │   ├── TextEngine
│       │   ├── Chunker/ChunkStore
│       │   ├── EmbeddingService / VectorStore
│       │   ├── ConceptMap* / ConceptMapStore
│       │   ├── ChapterSummaryService / BookSynopsisService
│       │   ├── BookChatRouter / ReaderAgentService
│       │   └── AgentTools / BookContext
│       └── ReaderUI/           # UIKit view controllers
│           ├── NativePageViewController
│           ├── WebPageViewController
│           ├── ReaderViewController
│           └── BookChatViewController
├── scripts/                    # Reproducible build automation
└── project.yml                 # XcodeGen project definition
```

## Design Decisions

**Native TextKit default, HTML fallback**: Native pagination provides clean layout and selection with predictable performance. HTML WKWebView remains available for fidelity with complex publisher styling.

**On-device embeddings**: The 128MB bge-small-en model runs locally via Core ML. No network calls are required for semantic search.

**Tool-calling agent**: The LLM retrieves evidence via tools and produces a final response only after retrieval.

**Execution traces**: Each response stores tool calls and results for debugging and transcript export.

## Requirements

- Xcode 15+
- iOS 17.0+ (iPad)
- [Mint](https://github.com/yonaskolb/mint) (for XcodeGen)
- OpenRouter API key

### Model Conversion (one-time)

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

Centralized logging via the shared helper:

```swift
private static let logger = Log.logger(category: "feature")
Self.logger.info("Event: \(value, privacy: .public)")
```

### Debug Transcript

Tap the doc icon in chat to copy the full LLM transcript, including tool calls and results.

### AI-Assisted Development

See `AGENTS.md` for the workflow, simulator management, logging standards, and deployment verification.

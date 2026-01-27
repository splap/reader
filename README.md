# Reader

An iPadOS EPUB reader with an AI assistant that can search, summarize, and answer questions about your books.

## What It Does

Select text while reading, ask the AI about it, and get answers grounded in evidence from the book.

**Example interactions:**
- "Summarize what just happened in this chapter and how it ties to the main plot."
- "Is this place real? If so, show it on a map and explain the reference."
- "Give me the character’s arc: intro, pivotal moment, and latest mention."

## Agent Tools

The LLM has access to these tools for answering questions:

| Tool | What it does |
|------|--------------|
| `lexical_search` | Find exact words/phrases in the book (FTS5 full-text search) |
| `semantic_search` | Find conceptually similar passages (vector embeddings) |
| `book_concept_map_lookup` | Look up characters, themes, and events by name |
| `get_surrounding_context` | Get text before/after a position ("what happens next?") |
| `get_chapter_summary` | Summarize a chapter (generated on demand, cached) |
| `get_book_synopsis` | Summarize the whole book with characters and themes |
| `get_book_structure` | Get the table of contents |
| `get_current_position` | Get reader's current location in the book |
| `wikipedia_lookup` | Look up real-world facts (people, places, events) |
| `show_map` | Display an inline map for a location |
| `render_image` | Display an inline image |

## Quick Start

```bash
# Install dependencies and generate Xcode project
./scripts/bootstrap

# Build and run on simulator
./scripts/run &

# Run tests
./scripts/test
```

Set your OpenRouter API key in app settings after launching.

## Requirements

- Xcode 15+, iOS 17.0+ (iPad)
- [Mint](https://github.com/yonaskolb/mint) for XcodeGen
- OpenRouter API key

**One-time model conversion** (for on-device semantic search):
```bash
uv run --with transformers --with torch --with coremltools python scripts/convert_bge_to_coreml.py
```

## How It Works

### Book Indexing

When you import a book, Reader builds search indexes in the background:

1. **Lexical index** — SQLite FTS5 for exact word/phrase search
2. **Vector index** — HNSW (via USearch) with bge-small-en embeddings for semantic search
3. **Concept map** — Extracted entities, themes, and events for routing queries

Chapter summaries and book synopses are generated on demand and cached.

### Agent Architecture

The agent uses a tool-first approach: it starts with minimal context and retrieves what it needs.

1. Route the question (book-specific vs general knowledge)
2. If book-related, search for evidence first
3. Answer with citations from retrieved passages

Guardrails: max 8 tool calls per question, evidence required for book claims.

## Architecture

```
Reader/
├── App/                           # Thin app shell + resources
├── Packages/ReaderKit/
│   └── Sources/
│       ├── ReaderCore/            # Domain logic (EPUB, search, agent)
│       └── ReaderUI/              # UIKit view controllers
├── scripts/                       # Build automation
└── project.yml                    # XcodeGen project definition
```

**Rendering:** WKWebView with CSS multi-column pagination. One spine item (chapter) is loaded at a time for deterministic layout.

**Position Tracking:** Uses EPUB CFI (Canonical Fragment Identifiers) for layout-independent position restore. Positions survive font size changes and device rotation.

## Development

| Script | Purpose |
|--------|---------|
| `bootstrap` | Install deps, generate Xcode project |
| `build` | Deterministic xcodebuild |
| `run` | Build, install, launch, stream logs |
| `test` | Unit tests (`test ui` for UI tests) |
| `lint` | SwiftLint + SwiftFormat |

See `CLAUDE.md` for AI-assisted development workflow and architecture details.

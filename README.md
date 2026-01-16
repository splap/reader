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
| Book Search | Full-text search across all chapters |
| Wikipedia Lookup | Fetch summaries and images inline |
| Map Display | MapKit snapshots rendered in chat |
| Conversation History | Persisted with full execution traces |
| Reading Position | Auto-saved per book |

## Architecture

```
Reader/
├── App/                        # Thin app shell
├── Packages/ReaderKit/
│   └── Sources/
│       ├── ReaderCore/         # Domain logic (no UIKit)
│       │   ├── EPUBLoader      # EPUB extraction & parsing
│       │   ├── ReaderAgentService  # LLM agent with tool loop
│       │   ├── AgentTools      # Book search, Wikipedia, maps
│       │   └── BookContext     # Provides content to tools
│       └── ReaderUI/           # UIKit view controllers
│           ├── ReaderViewController   # Main reader
│           ├── WebPageViewController  # WKWebView + JS bridge
│           └── BookChatViewController # Chat interface
├── scripts/                    # Reproducible build automation
└── project.yml                 # XcodeGen project definition
```

### Design Decisions

**WKWebView over TextKit**: EPUB content is HTML/CSS. Rather than converting to attributed strings, render natively in a web view with CSS column pagination. Trade-off: text selection requires a JavaScript bridge.

**SPM Package Architecture**: All feature code lives in `ReaderKit` as a Swift Package. The app target is a thin shell. This enables fast incremental builds and clear dependency boundaries.

**Tool-Calling Agent**: The LLM uses a multi-turn tool-calling loop. When the model needs book content, it calls `search_book`. When it needs external info, it calls `wikipedia_lookup`. Results feed back into the conversation until the model produces a final response.

**Execution Traces**: Every LLM response includes a trace of what tools were called, with arguments and results. These traces persist with the conversation for debugging.

## Requirements

- Xcode 15+
- iOS 17.0+ (iPad)
- [Mint](https://github.com/yonaskolb/mint) (for XcodeGen)
- OpenRouter API key

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

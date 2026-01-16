# Reader

An iPadOS EPUB reader with built-in LLM chat for asking questions about your books.

## Features

- **EPUB Reading**: Reflowable, paginated reading with WKWebView and CSS columns
- **LLM Chat**: Select text and ask questions via OpenRouter API
- **Tool-Augmented Responses**: LLM can search book content, look up Wikipedia, show maps
- **Library Management**: Import EPUBs, track reading position, conversation history
- **Customization**: Adjustable font scale, text justification

## Architecture

```
Reader/
├── App/                    # Thin app target (wiring + assets)
│   └── Sources/
├── Packages/ReaderKit/     # All feature code as SPM package
│   └── Sources/
│       ├── ReaderCore/     # Models, services, EPUB parsing
│       └── ReaderUI/       # View controllers
└── scripts/                # Build automation
```

### Key Components

**ReaderCore**
- `EPUBLoader` / `NCXParser` - EPUB parsing and extraction
- `ReaderAgentService` - LLM chat with tool calling loop
- `AgentTools` - Search book, Wikipedia lookup, map display
- `ConversationStorage` - Persist chat history with execution traces
- `BookContext` - Provides book content to LLM tools

**ReaderUI**
- `LibraryViewController` - Book list and import
- `ReaderViewController` - Main reader with WebView
- `BookChatViewController` - Chat interface with debug transcript
- `ChatContainerViewController` - Chat + conversation drawer

## Requirements

- macOS with Xcode 15+
- iOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation
- OpenRouter API key for LLM features

## Setup

```bash
# Install dependencies and generate Xcode project
./scripts/bootstrap

# Build
./scripts/build

# Run on simulator (tails logs - runs indefinitely)
./scripts/run &

# Run tests
./scripts/test          # Unit tests
./scripts/test ui       # UI tests
./scripts/test all      # All tests
```

## Configuration

Set your OpenRouter API key in the app settings, or via `OpenRouterConfig.apiKey`.

## Scripts

| Script | Purpose |
|--------|---------|
| `./scripts/bootstrap` | Install deps, generate Xcode project |
| `./scripts/build` | Build with xcodebuild |
| `./scripts/run` | Build, install, launch, tail logs |
| `./scripts/test` | Run unit/UI tests |
| `./scripts/lint` | SwiftLint / SwiftFormat |
| `./scripts/load-test-books` | Copy test EPUBs to simulator |

## Development

The project uses XcodeGen (`project.yml`) to generate the Xcode project. After modifying `project.yml` or package structure, run `./scripts/bootstrap`.

### Logging

Uses OSLog with subsystem `com.splap.reader`:

```swift
import OSLog
private static let logger = Log.logger(category: "my-feature")
Self.logger.info("Message: \(value, privacy: .public)")
```

View logs:
```bash
xcrun simctl spawn booted log stream --style compact --predicate 'subsystem == "com.splap.reader"'
```

### Debug Transcript

The chat view has a doc icon button that copies the full LLM transcript to clipboard - useful for debugging what context was sent and what responses came back.

## License

Private project.

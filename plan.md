# Agent Tools Revision Plan

## Goal

Revise agent tool definitions to be clear, distinct, and well-described so an LLM knows exactly when to use each tool. In a tool-first architecture, these descriptions are the most important text in the application.

## Changes

### Tools to Remove

1. **`get_chapter_text`** — Token bomb. Returns entire chapter raw text which is rarely useful and expensive. The model should use targeted searches instead.

2. **`get_character_mentions`** — Redundant. Implementation is identical to `search_content` (same `context.searchBook` call). If we want character-specific behavior later, it should leverage concept map entity data.

### Tools to Rename

1. **`search_content` → `lexical_search`** — Current name is vague. "Lexical" makes clear this is exact/fuzzy word matching, distinct from semantic search.

### Description Rewrites

All descriptions should:
- Tell the model WHEN to use the tool (use cases)
- Tell the model WHAT it returns
- Distinguish from similar tools
- Omit implementation details (caching, on-demand generation)

#### `get_current_position`
```
Get the reader's current position: chapter name, progress percentage, and block location.
Use this to understand where the reader is in the book before answering context-dependent questions.
```

#### `lexical_search` (was `search_content`)
```
Search for exact word or phrase matches in the book text. Uses full-text indexing with BM25 ranking.
Use this for:
- Finding specific names, terms, or phrases
- Locating exact quotes
- Counting occurrences of a word
Does NOT find conceptual matches — use semantic_search for that.
Returns: matching passages with surrounding context.
```

#### `semantic_search`
```
Search for passages by meaning, even without exact word matches. Uses vector embeddings to find conceptually similar text.
Use this for:
- Abstract questions ("passages about betrayal")
- Thematic queries ("where does the book discuss mortality?")
- When lexical_search returns no results but the concept should exist
Returns: passages ranked by semantic similarity with relevance scores.
```

#### `book_concept_map_lookup`
```
Look up the book's concept map to find which chapters discuss a topic. The concept map contains pre-extracted:
- Entities (characters, places, organizations)
- Themes (abstract concepts)
- Events (significant plot points)
Use this FIRST to scope searches to relevant chapters, saving tool budget.
Returns: matching entities/themes/events with their chapter locations.
```

#### `get_surrounding_context`
```
Get text blocks before and after a specific position. Use this for positional expansion:
- "What happens next?" — expand forward from current position
- "What led to this?" — expand backward from current position
- Understanding context around a user's selection
NOT for finding things — use lexical_search or semantic_search for that.
```

#### `get_book_structure`
```
Get the book's table of contents: title, author, and all chapter names with IDs.
Use this to:
- Answer "how many chapters?" or "what are the chapter names?"
- Get chapter IDs for scoped searches
- Understand the book's organization
```

#### `get_chapter_summary`
```
Get a summary of a specific chapter including key plot points and characters mentioned.
Use for questions like "what happens in chapter 3?" or to understand a chapter without searching through it.
Returns: narrative summary, key points, characters mentioned.
```

#### `get_book_synopsis`
```
Get a high-level synopsis of the entire book including main characters and themes.
Use for broad questions like "what is this book about?" or "who are the main characters?"
NOT for specific plot details — use chapter summaries or searches for those.
Returns: plot overview, main characters with descriptions, key themes.
```

#### `wikipedia_lookup`
*(Keep as-is — already excellent)*

#### `show_map`
```
Display an inline map for a real-world location.
Use when the user asks "where is X?" or wants to see a place on a map.
Only works for real places — not fictional locations from the book.
```

#### `render_image`
```
Display an image inline in chat.
Use when the user asks what something looks like and you have an image URL (typically from wikipedia_lookup).
Use sparingly — only when a visual genuinely helps answer the question.
```

## Implementation Steps

1. Remove `get_chapter_text` tool definition and executor case
2. Remove `get_character_mentions` tool definition and executor case
3. Rename `search_content` to `lexical_search` (definition, executor case, any references)
4. Update all tool descriptions per above
5. Update `allTools` array to reflect removals
6. Run tests to ensure nothing breaks

## Files to Modify

- `Packages/ReaderKit/Sources/ReaderCore/AgentTools.swift` — All changes here

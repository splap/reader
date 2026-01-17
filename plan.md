# Tool-First Book QA Architecture

## Goal

Answer detailed and high-level questions about a book without preloading large context, by forcing the model to retrieve only what it needs.

## Core Principle

**No prompt stuffing.** The model starts with minimal context and builds its own context via tools.

## Preprocessing (One-Time)

### Artifacts created at ingest

1. **Book Manifest**

   * Chapters/spine list, titles, ordering, and stable IDs.
2. **Chunk Store**

   * Raw text split into addressable chunks with locations: `(chapter_id, chunk_id, offset_range)`.
   * **Default chunking:** 800 tokens with 10% overlap (narrative);

     * allow per-book overrides: 512 tokens (dense/technical), 1024 tokens (poetry/long-form).
3. **Lexical Search Index**

   * Exact/ranked search over chunks (SQLite FTS5) keyed by `chapter_id` for scoping.
4. **Semantic Vector Index**

   * On-device embeddings for each chunk + ANN index (HNSW) keyed by the same `chunk_id`.
5. **Book Concept Map**

   * Compact routing metadata:

     * entities → chapter_ids
     * themes/concepts → chapter_ids
     * major events → chapter_ids
   * **Size targets:** ~50–200 entities, ~25–100 themes, ~50–200 events for a typical book.
   * **Hard caps (to preserve “minimal context”):**

     * entities ≤ 500, themes ≤ 200, events ≤ 500
     * each item links to ≤ 24 chapters (or top-N by evidence)

### Book Concept Map construction (specified)

**Inputs (deterministic signals)**

* Per chapter:

  * top keywords/keyphrases (TF-IDF over unigrams/bigrams)
  * high-salience capitalized spans (entity candidates)
  * co-occurrence windows (entity pairs in same paragraph/window)
  * semantic centroids (optional): average of chunk embeddings per chapter for clustering

**Normalization (LLM-backed; network LLM assumed available)**

* Canonicalize entity candidates:

  * merge aliases, label type (person/place/etc.), keep chapter coverage.
* Normalize theme clusters:

  * assign stable IDs, short human-readable labels, and representative keywords.
* Label events:

  * convert event candidates into short human-readable labels.

**Theme clustering algorithm (specified)**

* Inputs:

  * per-chapter keyword vectors (TF-IDF)
  * per-chapter semantic centroid (mean of chunk embeddings)
* Similarity:

  * cosine similarity on centroids + keyword vector (weighted blend, default 70/30).
* Clustering:

  * agglomerative hierarchical clustering with a distance threshold (no explicit k).
  * choose threshold to target 25–100 themes with a hard cap of 200.
  * deterministic: stable ordering + fixed threshold yields repeatable clusters.

**Event derivation without an LLM**

* Events are optional. If LLM labeling is unavailable:

  * emit event candidates as `(participants, chapter_ids, evidence pointers)` without a human-readable label.
  * UI shows a deterministic label derived from top participants (e.g., "Encounter: Achilles + Hector").

**Evidence tracking**

* Every concept map item stores:

  * `chapter_ids` + lightweight `evidence` (top terms and/or 1–2 short excerpt pointers).

### Artifacts created lazily (on demand)

6. **Chapter Summaries** (cached)

   * First request triggers summarization.
   * **Long chapters:** summarize per-chunk → per-section → chapter (map-reduce) with stable headings.
7. **Book Synopsis** (optional, cached)

   * Generated on demand by synthesizing chapter summaries and/or retrieved excerpts.

## Always-On Context (Very Small)

* Book identity (title, edition/translation).
* Available tools and their purpose.
* Rule: *Do not answer book-specific questions without retrieved evidence.*

## Tools

* `book_concept_map.lookup(query)` → candidate chapters (routing)
* `chapter_summary.get(chapter_id)` → narrative context (lazy + cached)
* `text_search(query, scope)` → exact excerpts + locations
* `semantic_search(query, scope, k)` → relevant chunks + locations
* `chunk.get(location_id)` → full chunk text
* *(optional)* `book_synopsis.get()` → book-level synthesis (lazy + cached)

## Implementation Choices (iOS-friendly)

### Exact text search

**Decision: ship our own SQLite with FTS5 enabled**

* Bundle a custom-built SQLite (amalgamation) compiled with `SQLITE_ENABLE_FTS5`.
* Use SQLite FTS5 virtual tables for ranked lexical search scoped by `chapter_id`.

### Semantic search (vector index)

**Decision: on-device embeddings + HNSW**

* Embeddings runtime: **MLX**.
* **Embedding model (fixed for v1): `BAAI/bge-small-en-v1.5`**

  * 384-dim embedding; retrieval-optimized; widely used.
  * License shown as MIT on the model repo.
* ANN index:

  * HNSW via **USearch** (Swift/iOS bindings).

## Runtime Flow

### 0) Router step (LLM, constrained)

For every user question, first run a small **routing prompt** (JSON output) that decides whether to use book tools.

**Inputs**

* user question
* loaded book metadata (title/author/translation)
* tool inventory

**Output**

* `route`: `NOT_BOOK | BOOK | AMBIGUOUS`
* `confidence` (0–1)
* `suggested_queries`: initial queries for `book_concept_map.lookup` and/or search

### 1) Resolve ambiguity (no user prompt by default)

If `route = AMBIGUOUS`, perform **one** `book_concept_map.lookup(question)`:

* If strong hits (entities/themes/events) → treat as `BOOK`.
* Else → treat as `NOT_BOOK`.

### 2) Book toolflow (only when `BOOK`)

1. **Scope**

   * `book_concept_map.lookup(question)` → candidate `chapter_ids`.
2. **Retrieve evidence**

   * Concrete/named/quotable questions → `text_search(query, scope=chapter_ids)` first.
   * Conceptual/abstract questions → `semantic_search(query, scope=chapter_ids, k=N)` first.
   * Escalate scope at most once (more chapters / whole book).
3. **Optional narrative support**

   * `chapter_summary.get(chapter_id)` for only the chapters involved (lazy + cached).
4. **Answer**

   * Grounded in retrieved excerpts.
   * Include chapter/location citations.
   * If evidence is insufficient, say so and report what was searched.

### 3) Normal flow (when `NOT_BOOK`)

Answer normally without using book tools.

## Defaults & Guardrails

* **Tool-call budget:** max **8** tool calls per user question (including router).

  * Typical: router (1) + concept map lookup (1) + retrieval (1–2) + chunk fetches (0–2) + summaries (0–1).
* **Single scope-escalation limit:** widen from candidate chapters → whole book at most once.
* **In-session caching:** cache concept-map lookups and retrieval results for the current conversation.
* **Evidence rule:** no book-specific answers without retrieved evidence or explicit “I could not find support.”
* **Degradation:** if embeddings/index are unavailable or failed, run **lexical-only book mode** (FTS5) and surface “Semantic search unavailable” in UI.

## Quality Hinges (Implementation Notes)

Overall answer quality depends primarily on three implementation details:

1. **Chunking strategy** — chunk size, overlap, and stable location IDs.
2. **Retrieval ranking** — FTS5 schema/tuning and semantic index quality.
3. **Router contract** — a tight, constrained router prompt and deterministic executor logic.

These are the load-bearing parts of the system and should be validated early.

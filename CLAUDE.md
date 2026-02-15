# CLAUDE.md — Xcode Agent Operating Context

> This file is your project context. Read it once at session start.
> Your task instructions come separately via directive.

---

## How You Work Here

You receive **surgical directives** with exact instructions. Follow them
literally — don't interpret, don't improve, don't add what wasn't asked for.

- **Build after every operation** (⌘B). Stop on failure.
- **Don't fix build errors by modifying code.** Report the error and stop.
- **Don't auto-rollback.** If a build fails, report the error and stop. Recommend a rollback if appropriate, but let the user decide.

---

## Things That Break If You're Not Careful

- **CloudKit constraints on SwiftData models:** No `@Attribute(.unique)`, all
  properties need defaults, all relationships must be optional. Violating these
  causes silent sync failures across devices.
- **Embedded marker pattern:** Weather data (`<!--weather:{...}-->`), images
  (`<!--image:{...}-->`), and iceberg tips (`<!--tip:...-->`) are stored as HTML
  comment markers in message content. Don't strip, reformat, or relocate
  these — the rendering pipeline depends on exact format.
- **Tool message pruning:** Messages with `isFinalResponse == false` are excluded
  from API payloads on subsequent turns. Don't change this flag's semantics.
- **Schema versioning:** Bump `AppConfig.buildVersion` before any SwiftData
  schema change. Deploy to ALL devices before making the change.
- **Bundle/entitlements:** Bundle prefix is JCC. iCloud container is
  iCloud.JCC.mac-claude-chat. The active entitlements file is
  `mac-claude-chat.entitlements` (hyphens), NOT `mac_claude_chat.entitlements`
  (underscores). Don't modify entitlements without explicit direction.

---

## File Map (34 Swift files, ~280 KB total)

```
mac-claude-chat/
│
│   ── Core ──
├── mac_claude_chatApp.swift           (1.9 KB)  @main, WindowGroup, menu commands
├── ContentView.swift                 (23.1 KB)  Pure view composition, observes ChatViewModel
├── ChatViewModel.swift               (27.5 KB)  All chat state + intent methods, system prompt
├── Models.swift                      (12.7 KB)  SwiftData models, ClaudeModel enum, RouterResponse,
│                                                WebToolCategory, WebToolSource, in-memory types,
│                                                provider configuration documentation
│
│   ── Services (Provider-Coupled) ──
├── ClaudeService.swift               (14.5 KB)  Streaming + singleShot HTTP to Anthropic API
│                                                PROVIDER-SPECIFIC: rewrite for xAI fork
├── ExtractionService.swift            (1.7 KB)  LLM-based JSON extraction abstraction
│                                                PROVIDER-SPECIFIC: ~10 lines change for xAI fork
│
│   ── Services (Provider-Agnostic) ──
├── RouterService.swift                (7.4 KB)  Haiku classifier, tip extraction, escalation logic
├── ToolService.swift                 (25.4 KB)  Provider-agnostic tool schemas, tool dispatch,
│                                                WeatherData, Tavily+Haiku weather extraction, web_lookup
│                                                Claude format converter (buildClaudeInputSchema)
├── SwiftDataService.swift            (24.2 KB)  Chat/message CRUD, context mgmt, web tools CRUD,
│                                                CloudKit dedup, turn ID backfill, default seeding
├── KeychainService.swift              (3.6 KB)  API key storage + env fallback (Anthropic, Tavily, OWM)
├── MessageSendingService.swift       (12.0 KB)  Send orchestration: route → filter → stream → tool loop
├── ContextFilteringService.swift      (5.1 KB)  Grade-based message filtering + API payload formatting
├── SlashCommandService.swift          (3.0 KB)  /command parsing (model overrides + local commands)
├── MessageContentParser.swift         (7.3 KB)  Single source of truth for marker parsing/stripping
├── ImageAttachmentManager.swift       (4.5 KB)  Image paste, drag/drop, file import processing
├── WebFetchService.swift              (9.9 KB)  HTTP fetch, HTML-to-text, URL resolution, fallback chains
│
│   ── Message Rendering ──
├── MessageBubble.swift                (8.0 KB)  Clean message layout: sparkle icon for assistant,
│                                                rounded bubble for user, context toggle, hover metadata
├── MarkdownMessageView.swift          (5.6 KB)  Markdown parsing, weather cards, code block dispatch
├── CodeBlockView.swift                (5.3 KB)  Fenced code + line numbers + copy button
├── SyntaxHighlighter.swift           (16.3 KB)  Regex tokenizer, Dracula palette
├── WeatherCardView.swift              (8.5 KB)  Gradient weather card with hourly forecast,
│                                                dual city-labeled datetime display
├── UserMessageContent.swift           (1.4 KB)  User message with images + text (no styling)
├── MessageImageView.swift             (1.8 KB)  Base64 image with expand/collapse
├── GradeControl.swift                 (0.8 KB)  Binary context toggle (ContextToggle view)
├── PendingImageThumbnail.swift        (1.4 KB)  Pre-send image preview
│
│   ── Utilities ──
├── ImageProcessor.swift               (4.1 KB)  Image downscale/encode + PendingImage
├── PlatformUtilities.swift            (0.8 KB)  PlatformColor, InputHeightPreferenceKey
├── SpellCheckingTextEditor.swift     (10.7 KB)  macOS NSTextView + paste interception + text file drop
│
│   ── Other Views ──
├── APIKeySetupView.swift              (6.1 KB)  Settings sheet for API keys
├── TokenAuditView.swift               (9.8 KB)  Per-turn token breakdown sheet
├── ChatExporter.swift                 (3.3 KB)  Selective markdown export + MarkdownFileDocument
├── WebToolManagerView.swift          (18.0 KB)  Web tool category/source manager with test-in-place

Entitlements:
├── mac-claude-chat.entitlements              Active (CloudKit, keychain, user-selected r/w)
├── mac_claude_chat.entitlements              Sandbox-only (app-sandbox, network, keychain)
```

---

## Conventions

- SwiftUI, `async/await`, `@Observable`/`@Environment`
- Enums as namespaces for stateless services
- Errors surface via `errorMessage` state + console print
- NotificationCenter bridges macOS menu commands → view state
- No external dependencies — Apple frameworks + direct HTTP only
- Always `python3`, never `python`
- **Cross-platform:** Supports macOS, iOS, iPadOS. Platform-specific code
  wrapped in `#if os(macOS)` / `#if !os(macOS)`. iOS uses gear button in
  sidebar for Settings access (no menu bar).

---

## Architecture

### Phase 2 Decomposition (Complete)

ContentView is a thin view layer that observes ChatViewModel.
All state and business logic lives in ChatViewModel and extracted services:

- **ChatViewModel** — owns all mutable state, coordinates services, builds
  system prompt. Injected with ModelContext via `configure(modelContext:)`.
- **MessageSendingService** — orchestrates the full send cycle as a single
  static `send()` call with progress callbacks. No UI state ownership.
- **ContextFilteringService** — grade-based turn filtering and API payload
  formatting. Pure data transformation, no UI dependencies.
- **ExtractionService** — abstracts LLM-based JSON extraction from unstructured
  text. Provider-coupled (~10 lines change for xAI fork). Fixes weather
  extraction bug (Sonnet → Haiku = 3x cost savings).
- **SlashCommandService** — parses `/command` prefixes. Model overrides
  (`/opus`, `/sonnet`, `/haiku`) are passthrough; local commands (`/help`,
  `/cost`, `/clear`, `/export`) execute immediately without API calls.
- **ImageAttachmentManager** — processes paste, drag/drop, and file import
  into PendingImage structs. Returns results for the caller to apply.
- **MessageContentParser** — single source of truth for all marker parsing
  and stripping (images, weather, tips). Used by rendering, export, API
  payload construction, and clipboard operations.

### Router + Iceberg Tips

- **Automatic model routing:** Every user message is classified by a Haiku
  `singleShot` call (RouterService) into HAIKU/SONNET tier. Opus is only
  available via `/opus` slash command. No manual model selector — user steers
  the router through natural language.
- **Tool-using queries route to Sonnet:** Weather queries, web searches, and
  any request requiring tool use are routed to Sonnet for reliable tool calling.
- **Confidence escalation:** If router confidence < 0.8, tier bumps up one level.
- **Iceberg tips:** Each assistant response generates a `<!--tip:...-->` marker
  (one-line summary, ~20 words). Tips are stripped from display, stored on
  `ChatMessage.icebergTip`, and fed to the router as lightweight conversation
  context instead of full history.
- **Metadata footer:** Assistant messages show model, token count, and cost
  on hover only (clean UI by default).
- **Per-message model tracking:** `ChatMessage.modelUsed` stores the model's
  raw enum value. Cost calculation sums actual per-message costs.

### Prompt Caching

Two cache breakpoints implemented:
1. **System prompt** — content block array with `cache_control: ephemeral`.
   Beta header `prompt-caching-2024-07-31` included.
2. **Last history message** — conversation history prefix cached via
   `cache_control` on the last message before the current turn.

Cache metrics logged: `[CACHE] 💾 {read} read, {written} written`.
First call pays 1.25x write; subsequent reads at 0.1x (90% discount).
Cache invalidates naturally when messages change.

### Weather Tool (Tavily + Haiku Extraction)

- **Data source:** Tavily web search replaces OpenWeatherMap. No OWM dependency.
- **Extraction pipeline:** Tavily fetches weather text → Haiku `singleShot`
  extracts structured JSON (city, temp, conditions, hourly, timezone offset)
  → parsed into `WeatherData` struct → rendered by `WeatherCardView`.
- **Hourly forecast:** Extracted when Tavily's source includes hourly data.
  Card gracefully hides the hourly strip when empty.
- **Datetime display:** Weather card shows dual city-labeled times.
  Same timezone = one line (e.g., "Wed 4:30 PM Catonsville").
  Different timezone = two lines (e.g., "Wed 2:30 PM Boise" /
  "Wed 4:30 PM Catonsville").
- **Markdown fence stripping:** Haiku JSON responses cleaned of backtick
  wrappers before parsing.
- **ToolResult.overheadTokens:** Weather extraction reports Haiku token
  consumption via associated values on `.weather` case.

### Web Tools

- **WebToolCategory + WebToolSource** — SwiftData models for user-configurable
  web sources, organized by category keyword with priority-ordered fallback.
- **WebFetchService** — HTTP fetch with HTML-to-text extraction, URL pattern
  resolution with `{placeholder}` substitution, and fallback chain execution.
- **web_lookup tool** — Claude can call `web_lookup` with a category keyword;
  the tool tries curated sources in priority order, falls back to Tavily
  general search if all sources fail.
- **WebToolManagerView** — NavigationSplitView manager with category/source
  CRUD, enable/disable toggles, drag-to-reorder priority, and test-in-place.

### Context Management

- **Binary toggle:** Each user message has a `textGrade` interpreted as boolean
  (0 = excluded, >0 = included). No threshold — just in or out.
- **Turn filtering:** Messages with `textGrade == 0` are excluded from API
  payloads as complete turns (user + assistant pair).
- **Visual dimming:** Excluded messages shown at 30% opacity.
- **ContextToggle:** Small circle (black = included, gray = excluded) appears
  next to user messages. Always visible on iOS, hover-only on macOS.

---

## Known Issues / Pending Work

- **Overhead token pricing:** Router and weather extraction overhead tokens
  are currently folded into `totalStreamInputTokens` / `totalStreamOutputTokens`
  in `MessageSendingService.send()`. They are priced at the primary model's
  rate (Sonnet/Opus), which overstates cost ~3x. Directive
  `directive-overhead-tokens-v2.md` adds separate `overheadInputTokens` /
  `overheadOutputTokens` fields to `ChatMessage` and `Message`, priced at
  Haiku rate in `calculateCost()`. Not yet applied.
- **Weather extraction model:** `executeWeather()` in `ToolService.swift`
  calls `singleShot` with `model: .fast` (Sonnet). Should be `model: .turbo`
  (Haiku) — this is a data extraction task, not a reasoning task. Fix when
  applying the overhead tokens directive.
- **Duplicate comment:** `ToolResult` enum has two identical doc comments
  (lines ~81-82 in ToolService.swift). Remove the duplicate.

---

## Schema

- **Current version:** `AppConfig.buildVersion = 8`
- **Models:** ChatSession, ChatMessage, WebToolCategory, WebToolSource
- **CloudKit container:** iCloud.JCC.mac-claude-chat

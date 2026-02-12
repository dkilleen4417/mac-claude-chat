# CLAUDE.md — Xcode Agent Operating Context

> This file is your project context. Read it once at session start.
> Your task instructions come separately via directive.

---

## How You Work Here

You receive **surgical directives** with exact instructions. Follow them
literally — don't interpret, don't improve, don't add what wasn't asked for.

- **Build after every operation** (⌘B). Stop on failure.
- **Don't fix build errors by modifying code.** Report the error and stop.
- **Revert failed operations** with the git command provided in the directive.

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

## File Map (31 Swift files)

```
mac-claude-chat/
│
│   ── Core ──
├── mac_claude_chatApp.swift          (~55)   @main, WindowGroup, menu commands
├── ContentView.swift                (~350)   Pure view composition, observes ChatViewModel
├── ChatViewModel.swift              (~390)   All chat state + intent methods, system prompt
├── Models.swift                     (~310)   SwiftData models, ClaudeModel enum, RouterResponse,
│                                             WebToolCategory, WebToolSource, in-memory types
│
│   ── Services ──
├── ClaudeService.swift              (~380)   Streaming + singleShot HTTP to Anthropic API
├── RouterService.swift              (~180)   Haiku classifier, tip extraction, escalation logic
├── ToolService.swift                (~420)   Tool definitions, dispatch, WeatherData, web_lookup
├── SwiftDataService.swift           (~480)   Chat/message CRUD, context mgmt, web tools CRUD,
│                                             CloudKit dedup, turn ID backfill, default seeding
├── KeychainService.swift            (~130)   API key storage + env fallback (Anthropic, Tavily, OWM)
├── MessageSendingService.swift      (~210)   Send orchestration: route → filter → stream → tool loop
├── ContextFilteringService.swift    (~100)   Grade-based message filtering + API payload formatting
├── SlashCommandService.swift         (~95)   /command parsing (model overrides + local commands)
├── MessageContentParser.swift       (~170)   Single source of truth for marker parsing/stripping
├── ImageAttachmentManager.swift     (~105)   Image paste, drag/drop, file import processing
├── WebFetchService.swift            (~210)   HTTP fetch, HTML-to-text, URL resolution, fallback chains
│
│   ── Message Rendering ──
├── MessageBubble.swift              (~160)   Message row + hover grade controls + dimming + metadata
├── MarkdownMessageView.swift        (~170)   Markdown parsing, weather cards, code block dispatch
├── CodeBlockView.swift              (~150)   Fenced code + line numbers + copy button
├── SyntaxHighlighter.swift          (~380)   Regex tokenizer, Dracula palette
├── WeatherCardView.swift            (~165)   Gradient weather card with hourly forecast
├── UserMessageContent.swift          (~50)   User message with images + text
├── MessageImageView.swift            (~60)   Base64 image with expand/collapse
├── GradeControl.swift                (~40)   0-5 dot grade picker
├── PendingImageThumbnail.swift       (~47)   Pre-send image preview
│
│   ── Utilities ──
├── ImageProcessor.swift             (~125)   Image downscale/encode + PendingImage
├── PlatformUtilities.swift           (~37)   PlatformColor, InputHeightPreferenceKey
├── SpellCheckingTextEditor.swift    (~235)   macOS NSTextView + paste interception + text file drop
│
│   ── Other Views ──
├── APIKeySetupView.swift            (~185)   Settings sheet for API keys
├── TokenAuditView.swift             (~240)   Per-turn token breakdown sheet
├── ChatExporter.swift               (~100)   Selective markdown export + MarkdownFileDocument
├── WebToolManagerView.swift         (~380)   Web tool category/source manager with test-in-place

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

---

## Architecture

### Phase 2 Decomposition (Complete)

ContentView is a thin view layer (~350 lines) that observes ChatViewModel.
All state and business logic lives in ChatViewModel and extracted services:

- **ChatViewModel** — owns all mutable state, coordinates services, builds
  system prompt. Injected with ModelContext via `configure(modelContext:)`.
- **MessageSendingService** — orchestrates the full send cycle as a single
  static `send()` call with progress callbacks. No UI state ownership.
- **ContextFilteringService** — grade-based turn filtering and API payload
  formatting. Pure data transformation, no UI dependencies.
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
- **Confidence escalation:** If router confidence < 0.8, tier bumps up one level.
- **Iceberg tips:** Each assistant response generates a `<!--tip:...-->` marker
  (one-line summary, ~20 words). Tips are stripped from display, stored on
  `ChatMessage.icebergTip`, and fed to the router as lightweight conversation
  context instead of full history.
- **Metadata footer:** Each assistant message displays model used, token count,
  and cost in caption-style text below the response.
- **Per-message model tracking:** `ChatMessage.modelUsed` stores the model's
  raw enum value. Cost calculation sums actual per-message costs.

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

- **Grade system:** Each user message has a `textGrade` (0-5, default 5).
  Each chat session has a `contextThreshold` (0-5, default 0).
- **Turn filtering:** Messages with `textGrade < threshold` are excluded from
  API payloads as complete turns (user + assistant pair).
- **Visual dimming:** Messages below threshold are dimmed in the UI.
- **Bulk actions:** "Grade All 5" and "Grade All 0" for quick context control.

---

## Schema

- **Current version:** `AppConfig.buildVersion = 7`
- **Models:** ChatSession, ChatMessage, WebToolCategory, WebToolSource
- **CloudKit container:** iCloud.JCC.mac-claude-chat

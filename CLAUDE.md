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

## File Map (23 Swift files)

```
mac-claude-chat/
│
│   ── Core ──
├── mac_claude_chatApp.swift          (60)   @main, WindowGroup, menu commands
├── ContentView.swift               (~1400)  Main view + all app logic + publishChat
├── Models.swift                     (~260)  SwiftData models, ClaudeModel enum, RouterResponse
│
│   ── Services ──
├── ClaudeService.swift              (~390)  Streaming + singleShot HTTP to Anthropic API
├── RouterService.swift              (~150)  Haiku classifier, tip extraction, escalation logic
├── ToolService.swift                (422)   Tool definitions, dispatch, WeatherData
├── SwiftDataService.swift           (~420)  CRUD + CloudKit deduplication
├── KeychainService.swift            (128)   API key storage + env fallback
│
│   ── Message Rendering ──
├── MessageBubble.swift              (~180)   Message row + hover grade controls + dimming + metadata footer
├── MarkdownMessageView.swift        (189)   Markdown parsing, dispatches to cards/code
├── CodeBlockView.swift              (147)   Fenced code + line numbers + copy button
├── SyntaxHighlighter.swift          (381)   Regex tokenizer, Dracula palette
├── WeatherCardView.swift            (164)   Gradient weather card
├── UserMessageContent.swift          (50)   User message with images + text
├── MessageImageView.swift            (60)   Base64 image with expand/collapse
├── GradeControl.swift                (40)   0-5 dot grade picker
├── PendingImageThumbnail.swift       (47)   Pre-send image preview
│
│   ── Utilities ──
├── ImageProcessor.swift             (124)   Image downscale/encode + PendingImage
├── PlatformUtilities.swift           (37)   PlatformColor, InputHeightPreferenceKey
├── SpellCheckingTextEditor.swift    (232)   macOS NSTextView + paste interception
│
│   ── Other Views ──
├── APIKeySetupView.swift            (184)   Settings sheet for API keys
├── TokenAuditView.swift             (238)   Per-turn token breakdown sheet
├── ChatExporter.swift               (101)   Selective markdown export + MarkdownFileDocument

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

## Architecture: Router + Iceberg Tips

- **Automatic model routing:** Every user message is classified by a Haiku
  `singleShot` call (RouterService) into HAIKU/SONNET/OPUS tier. No manual
  model selector — user steers the router through natural language.
- **Confidence escalation:** If router confidence < 0.7, tier bumps up one level.
- **Iceberg tips:** Each assistant response generates a `<!--tip:...-->` marker
  (one-line summary, ~20 words). Tips are stripped from display, stored on
  `ChatMessage.icebergTip`, and fed to the router as lightweight conversation
  context instead of full history.
- **Metadata footer:** Each assistant message displays model used, token count,
  and cost in caption-style text below the response.
- **Per-message model tracking:** `ChatMessage.modelUsed` stores the model's
  raw enum value. Cost calculation sums actual per-message costs.
- **Schema version:** `AppConfig.buildVersion = 6` (icebergTip + modelUsed fields).
- **Temporal reasoning:** System prompt enforces get_datetime → compute date →
  include date in search queries for any relative time reference.

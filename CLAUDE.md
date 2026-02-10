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
- **Embedded marker pattern:** Weather data (`<!--weather:{...}-->`) and images
  (`<!--image:{...}-->`) are stored as HTML comment markers in message content.
  Don't strip, reformat, or relocate these — the rendering pipeline depends on
  exact format.
- **Tool message pruning:** Messages with `isFinalResponse == false` are excluded
  from API payloads on subsequent turns. Don't change this flag's semantics.
- **Schema versioning:** Bump `AppConfig.buildVersion` before any SwiftData
  schema change. Deploy to ALL devices before making the change.
- **Bundle/entitlements:** Bundle prefix is JCC. iCloud container is
  iCloud.JCC.mac-claude-chat. Don't modify entitlements without explicit direction.

---

## File Map (21 Swift files, 4,922 lines total)

```
mac-claude-chat/
│
│   ── Core ──
├── mac_claude_chatApp.swift          (69)   @main, WindowGroup, menu commands
├── ContentView.swift               (1329)   Main view + all app logic
├── Models.swift                     (227)   SwiftData models, ClaudeModel enum
│
│   ── Services ──
├── ClaudeService.swift              (342)   Streaming HTTP to Anthropic API
├── ToolService.swift                (422)   Tool definitions, dispatch, WeatherData
├── SwiftDataService.swift           (406)   CRUD + CloudKit deduplication
├── KeychainService.swift            (128)   API key storage + env fallback
│
│   ── Message Rendering ──
├── MessageBubble.swift              (106)   Message row + grade controls + dimming
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
```

---

## Conventions

- SwiftUI, `async/await`, `@Observable`/`@Environment`
- Enums as namespaces for stateless services
- Errors surface via `errorMessage` state + console print
- NotificationCenter bridges macOS menu commands → view state
- No external dependencies — Apple frameworks + direct HTTP only
- Always `python3`, never `python`

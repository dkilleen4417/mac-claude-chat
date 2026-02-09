# CLAUDE.md — Project Memory for mac-claude-chat

> This file is read by Claude Code (CLI and Desktop Code tab) automatically,
> and by the Xcode Claude Agent when it explores the project structure.
> It establishes shared context so any Claude instance — planning or implementing —
> works from the same understanding.

---

## Developer

Andrew ("Drew") Killeen — 74-year-old retired engineer, 54 years of coding
experience (FORTRAN IV through modern Swift/Python). Approaches development as a
"gardener not a farmer" — careful cultivation over mass production. MBA from Loyola,
career at Baltimore Gas & Electric in HVAC engineering. Lives in Catonsville, MD
with his partner Jane.

---

## What This App Is

mac-claude-chat is Drew's personal AI chat application — a native macOS/iOS app
built in SwiftUI that talks to the Anthropic Claude API. It's not a wrapper around
a web interface; it's a from-scratch native client with streaming responses, tool
calling, markdown rendering, multi-chat management, and cross-device sync via
CloudKit.

Drew built this to have a chat experience he fully controls — his own system prompt,
his own tools, his own data, synced across his Mac Studio, iPhone, and iPad. It's
a hobby project but built to production standards.

---

## Architecture at a Glance

The app follows a straightforward layered architecture with no external dependencies
beyond Apple's frameworks and direct HTTP API calls. There is no SwiftUI package
manager dependency, no Alamofire, no third-party markdown library — everything is
built from Foundation and SwiftUI primitives.

```
┌──────────────────────────────────────────────────┐
│  mac_claude_chatApp.swift                        │
│  @main entry point                               │
│  WindowGroup + modelContainer for SwiftData      │
│  macOS menu commands via NotificationCenter      │
└──────────────┬───────────────────────────────────┘
               │
┌──────────────▼───────────────────────────────────┐
│  ContentView.swift (~2400 lines)                 │
│  The entire UI lives here:                       │
│  - NavigationSplitView (sidebar + detail)        │
│  - Chat list management                          │
│  - Message display with streaming                │
│  - Input bar with model selector + image attach  │
│  - Tool activity indicators                      │
│  - The agentic tool loop (sendMessage)           │
│  Also contains: MessageBubble, MarkdownMessage,  │
│  CodeBlockView, WeatherCardView, ImageProcessor, │
│  SpellCheckingTextEditor, SyntaxHighlighter      │
└──────┬──────────┬──────────┬─────────────────────┘
       │          │          │
┌──────▼───┐ ┌───▼─────┐ ┌──▼──────────────┐
│ Claude   │ │ Tool    │ │ SwiftData       │
│ Service  │ │ Service │ │ Service         │
│          │ │         │ │                 │
│ Streaming│ │ Defines │ │ CRUD for chats  │
│ HTTP to  │ │ tools,  │ │ and messages    │
│ Anthropic│ │ dispatches│ │ via ModelContext│
│ API with │ │ & executes│ │                │
│ SSE parse│ │ them    │ │ Deduplication   │
│          │ │         │ │ for CloudKit    │
└──────────┘ └─────────┘ └────────┬────────┘
                                  │
                          ┌───────▼────────┐
                          │ SwiftData +    │
                          │ CloudKit       │
                          │                │
                          │ ChatSession    │
                          │ ChatMessage    │
                          │                │
                          │ iCloud sync    │
                          │ across devices │
                          └────────────────┘

┌──────────────┐  ┌────────────────────┐
│ Keychain     │  │ APIKeySetupView    │
│ Service      │  │                    │
│              │  │ Settings sheet for │
│ Stores keys: │  │ entering/updating  │
│ - Anthropic  │  │ all API keys with  │
│ - Tavily     │  │ Keychain links     │
│ - OWM        │  │                    │
│              │  │ Also validates key │
│ Env fallback │  │ format (sk-ant-)   │
└──────────────┘  └────────────────────┘
```

---

## How the Pieces Work

### The Tool Loop (the heart of sendMessage)

The most architecturally significant code is the tool-calling loop in
`ContentView.sendMessage()`. It doesn't just send a message and display a
response — it runs an iterative agent loop:

1. Send the full conversation + tool definitions to Claude's streaming API
2. Parse the streamed response for both text chunks and tool_use blocks
3. If Claude requests tools (stop_reason == "tool_use"):
   - Execute each tool via `ToolService.executeTool()`
   - Display activity indicators ("🔍 Searching: ...")
   - Append the assistant's response and tool results to the API messages
   - Loop back to step 1 (up to 5 iterations)
4. When Claude finishes (stop_reason == "end_turn"), save the complete response

This means the app supports multi-step tool chains — Claude can search the web,
see results, then check the weather, then compose a response using both — all
in a single user message.

### ClaudeService — Two Streaming Methods

ClaudeService has two streaming paths, both using URLSession byte streaming:

- `streamMessage()` — Simple text-only streaming with `onChunk`/`onComplete`
  callbacks. Uses typed Codable structs for parsing. This was the original
  implementation and is currently unused but preserved.

- `streamMessageWithTools()` — The active method. Handles mixed content blocks
  (text + tool_use) using manual JSONSerialization parsing because the response
  structure is polymorphic (text deltas vs. input_json_delta). Returns a
  `StreamResult` containing text, tool calls, stop reason, and token counts.

Both methods authenticate with `x-api-key` header and parse Anthropic's SSE
stream format (data: prefixed lines).

### ToolService — Separated Tool Execution

ToolService is deliberately separated from ClaudeService as a clean separation
of concerns. ClaudeService handles API communication; ToolService handles tool
definition, dispatch, and execution. This keeps each service focused and makes
it easy to add new tools without touching the streaming logic.

Current tools:
- **get_datetime** — Always available. Returns Eastern time. No API key needed.
- **search_web** — Conditional on Tavily API key. Uses Tavily's advanced search
  with AI summary. Returns up to 6 results.
- **get_weather** — Conditional on OpenWeatherMap key. Two-step: geocode location,
  then fetch weather via One Call API 3.0 (`/data/3.0/onecall`). Returns current
  conditions, daily high/low, and 6-hour forecast in a single call. Defaults to
  Catonsville, MD. Imperial units. Returns structured data (`WeatherData` +
  `HourlyForecast` array) for rich UI card rendering.

Tool definitions are only included in API requests when their keys are present
(checked via KeychainService at call time, not at app startup).

### Rich Tool Results — The Embedded Marker Pattern

Tools can return both plain text (for Claude) and structured data (for the UI).
This is handled by the `ToolResult` enum:

- `.plain(String)` — Text-only result (datetime, search, errors)
- `.weather(text:data:)` — Text for Claude + `WeatherData` struct for the card.
  `WeatherData` includes current conditions, icon code (for day/night SF Symbol
  variants), daily high/low, observation timestamp (`observationTime` as Unix
  epoch from `current.dt`), timezone offset (`timezoneOffset` in seconds from
  UTC, from the API's top-level `timezone_offset` — enables correct local time
  display for any queried location, not just Eastern), and a `[HourlyForecast]`
  array (next 6 hours with per-hour temp, conditions, icon code, and precipitation
  probability). Both timestamp fields are `Int`, remain `Codable`, and are
  backward-compatible — old persisted cards without them render gracefully.

When a tool returns structured data, the tool loop:
1. Sends the plain text to Claude as the `tool_result` content
2. Collects the structured data as a JSON marker: `<!--weather:{...}-->`
3. Prepends all markers to the saved message content

The `MarkdownMessageView` parser detects these markers, extracts the JSON,
renders the appropriate card view (e.g., `WeatherCardView`), then strips the
marker before rendering the text. This persists naturally in SwiftData — no
schema changes, no CloudKit compatibility issues.

This pattern is extensible: new tools can define their own marker prefix
(e.g., `<!--search:...-->`) and card view, following the same flow.

### Image Attachments — The Same Marker Pattern

Users can attach images (screenshots, photos) to messages. Images are processed
and stored using the same embedded marker pattern as weather data:

**Input methods:**
- **Paste (⌘V)** — Primary path for macOS screenshots. `PasteInterceptingTextView`
  (NSTextView subclass) intercepts paste, checks for image data on the pasteboard.
- **Drag and drop** — Drop image files onto the input area. Same NSTextView subclass
  overrides `performDragOperation` to intercept file drops before they become text.
- **File picker** — Attachment button (photo.badge.plus) opens `.fileImporter`.

**Processing pipeline (`ImageProcessor` enum):**
1. Accept raw image data (PNG, JPEG, TIFF, etc.)
2. Downscale to 1024px max on long edge (retina screenshots → reasonable size)
3. Encode as JPEG at 0.7 quality
4. Return base64 string + media type

**Pending images UI:**
- `@State private var pendingImages: [PendingImage]` holds images awaiting send
- Thumbnail strip (60pt previews) appears above input bar when images are pending
- Each thumbnail has an X button to remove before sending

**Persistence (marker pattern):**
```
<!--image:{"id":"uuid","media_type":"image/jpeg","data":"base64..."}-->
user's text message here
```
Multiple images = multiple markers, one per line. `MessageBubble` parses these
markers, extracts images, renders via `MessageImageView` (click to expand),
then displays the cleaned text below.

**API format:**
When sending to Claude, image markers are converted to content blocks:
```json
{"role": "user", "content": [
  {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": "..."}},
  {"type": "text", "text": "What's in this screenshot?"}
]}
```
The `buildAPIMessage()` helper handles this conversion for both fresh sends
and when rebuilding conversation history from persisted messages.

### SwiftData + CloudKit Sync

The data layer uses two SwiftData @Model classes:

- **ChatSession** — A named conversation. Has chatId (string, used as display name),
  cumulative token counts, lastUpdated timestamp, isDefault flag, and a cascade
  relationship to ChatMessage.
- **ChatMessage** — A single message with role ("user"/"assistant"), content, and
  timestamp.

CloudKit compatibility imposes constraints:
- No `@Attribute(.unique)` — uniqueness is enforced in app logic
- All properties must have default values
- All relationships must be optional (hence `safeMessages` accessor)
- Deduplication runs on app launch to merge duplicate sessions created by
  multi-device race conditions

The "Scratch Pad" session is auto-created and pinned to the top of the sidebar.
It cannot be deleted, only cleared.

### The UI (all in ContentView)

The entire interface is a single `NavigationSplitView`:

- **Sidebar**: Header bar with "Chats" title and compose icon (square.and.pencil).
  Chat list sorted with Scratch Pad pinned first, then by recency. Each chat row
  has a three-dot context menu with Rename, Star (placeholder), Add to Project
  (placeholder), and Delete options. Swipe-to-delete also available on non-default
  chats. Chat rename updates the `chatId` in SwiftData via `renameChat()`.
- **Detail**: Header bar showing model + chat name. Scrolling message list with
  auto-scroll on new content. Streaming content shown in real-time with tool
  activity indicators. Input bar at bottom uses `SpellCheckingTextEditor` on macOS
  (NSTextView wrapper with spell checking enabled) or standard TextEditor on iOS.
  Return sends, Shift+Return inserts newline. The input area auto-sizes from 36pt
  (single line) to 200pt max, growing smoothly as the user types. Animation on
  height change. Model selector dropdown, token count, cost estimate, and Clear
  Chat below.

Message rendering handles markdown (via `AttributedString(markdown:)`) and
fenced code blocks with **syntax highlighting** via the `SyntaxHighlighter` enum —
a regex-based tokenizer that maps source code into colored `AttributedString` spans.
Supported languages: Python, Swift, JavaScript/TypeScript, JSON, Bash, plus a
generic fallback that highlights strings, comments, and numbers for unrecognized
languages. Language aliases are normalized (e.g., `py` → Python, `js` → JavaScript).
Color palette is Dracula-inspired: pink keywords, green strings, gray comments,
orange numbers, cyan types, blue function calls, yellow decorators/attributes.

`CodeBlockView` renders with a dark background (always dark, even in light system
appearance), line numbers in a fixed left gutter, a header bar with language label
and copy-to-clipboard button (clipboard icon → checkmark "Copied" feedback), and
horizontal scrolling for long lines. Inline code in prose gets monospaced font with
a visible gray background tint.

Rich tool results (like weather) render as inline cards above Claude's prose response.

The UI follows a Gemini-inspired clean aesthetic:
- Assistant messages sit directly on the canvas (no bubble background)
- User messages use a soft accent-color tint (15% opacity) instead of solid blue
- Message content is constrained to 720px max width and centered
- Increased spacing (24pt) between messages for better readability
- Smaller, subtler role indicator emojis (🧠/😎)

macOS menu commands (New Chat, Clear Chat, Delete Chat, Model Selection, API Key
Settings) are wired through `NotificationCenter` because SwiftUI's menu command
system can't directly access view state.

### Model Selection

Three Claude models are available, selectable via dropdown or keyboard shortcuts:
- ⌘1: Haiku 4.5 (fast/cheap, Drew's default)
- ⌘2: Sonnet 4.5
- ⌘3: Opus 4.6 (most capable/expensive)

Cost tracking is per-session, calculated from model-specific token pricing.

### API Key Management

KeychainService stores three keys under the service identifier "JCC.mac-claude-chat":
- Anthropic (required — app won't function without it)
- Tavily (optional — enables web search tool)
- OpenWeatherMap (optional — enables weather tool)

Each key falls back to environment variables (ANTHROPIC_API_KEY, TAVILY_API_KEY,
OWM_API_KEY) for development convenience. The APIKeySetupView sheet is force-
presented on first launch if no Anthropic key exists, and accessible anytime via
⌘, (Settings menu).

### Entitlements and Signing

The app has entitlements for:
- Keychain access groups (shared keychain for the app's bundle)
- iCloud container (iCloud.JCC.mac-claude-chat) for CloudKit sync
- CloudKit service
- Push notifications (development) for CloudKit change notifications

Paid Apple Developer account is active. The bundle identifier prefix is JCC.

---

## What's In Progress

The app is stable and fully functional as a single-provider (Anthropic) native
client. Multi-provider support was previously explored but has been abandoned —
the app's focus is on being the best Claude client it can be, not a generic
LLM frontend.

Recent additions:
- **Image attachments** — Users can attach screenshots and images to messages via
  paste (⌘V), drag-and-drop, or file picker. Images are downscaled to 1024px max,
  encoded as JPEG base64, and stored using the embedded marker pattern. Renders as
  clickable thumbnails in user messages (tap to expand). Full vision support for
  Claude to analyze images. See "Image Attachments" section above for details.
- **Syntax-highlighted code blocks** — `SyntaxHighlighter` enum provides regex-based
  tokenization for Python, Swift, JavaScript/TypeScript, JSON, Bash, with a generic
  fallback. Dracula-inspired color palette (pink keywords, green strings, gray
  comments, orange numbers, cyan types). `CodeBlockView` redesigned with dark theme
  background, line numbers gutter, language label header, and copy-to-clipboard button
  with "Copied" feedback. Inline code in prose gets monospaced font + gray background.
- **Dynamic input bar height** — `SpellCheckingTextEditor` reports content height via
  binding; input bar grows from 36pt to 200pt max as user types, with smooth animation.
  On iOS, uses hidden `Text` measurement via `GeometryReader`. Resets to compact size
  after sending.
- **Weather card visual upgrade** — `WeatherCardView` now uses condition-aware
  `LinearGradient` backgrounds keyed to `iconCode` (two-char prefix for condition,
  `d`/`n` suffix for day/night). Palettes range from warm sky-blue/golden (clear
  day) through steel grays (overcast) to deep navy (clear night) and dark purple
  (thunderstorm). All card text renders white/light for contrast. Observation
  timestamp formatted as "as of 3:13 PM" using the queried location's own timezone
  via `timezoneOffset` — a Boise query shows Mountain time, not Eastern.
  `WeatherData` gained two `Int` fields (`observationTime`, `timezoneOffset`);
  old persisted cards without them fall back gracefully (no timestamp shown,
  sensible default gradient).

Areas open for development:
- **Rich search results** — Apply the same marker pattern to web search for
  card-based result display.
- **Apple platform integration** — Shortcuts, widgets, Siri.
- **iOS image attachment** — Paste and file picker work; drag-and-drop needs iOS-specific handling.

---

## Development Workflow: Design-Build

This project uses a two-phase workflow that divides planning from implementation.
**Both phases use Claude, but different tools for different strengths.**

### Phase 1: Design (Claude.ai Chat or Claude Code planning mode)
- Specification, architecture, and design decisions
- Extended thinking and deep reasoning about tradeoffs
- Writing directives that describe *what* to build and *where things belong*
- Exploring alternatives before committing to an approach
- Output: A directive or goal description for Phase 2

### Phase 2: Build (Xcode Claude Agent — preferred for Swift/SwiftUI work)
- Implementation, compilation, visual verification
- The Xcode agent can build the project, see compiler errors, view SwiftUI
  previews, consult Apple documentation, and iterate autonomously
- It closes the build-test-verify loop that Claude Code cannot

### When to Use Claude Code Instead of Xcode Agent
- File operations outside Xcode (scripts, config, documentation)
- Complex multi-file refactors where you want step-by-step control
- Working with the Python/Streamlit/MongoDB stack (separate projects)
- When you need `ultrathink`-level planning before any code is written

---

## Directive Tiers for Xcode Agent

When handing work to the Xcode Claude Agent, match directive detail to complexity.

**Key principle:** The Xcode agent is a highly capable Claude instance integrated
into Apple's IDE. It can explore the project, read every file, build, see compiler
errors, view SwiftUI previews, consult Apple documentation, and iterate
autonomously. Directives should describe *what* to build and *why* — not *how* to
write the code. The agent writes better Swift from intent than from pre-baked
code blocks.

**Historical note:** The `directives/` folder contains detailed "cascade" directives
from early development when a less capable model was implementing code in Cursor
without a build-test loop. Those directives included exact find/replace blocks and
line numbers because the implementing agent couldn't iterate. **Do not use those
as templates.** They reflect a workflow that no longer applies.

### Writing Effective Directives (Claude.ai guidance)

When Claude.ai constructs a directive for the Xcode agent:

1. **State the goal clearly** — what capability should exist when this is done?
2. **Explain the *why*** — what's the reasoning behind the approach? What problem
   does this solve? The agent makes better decisions with context.
3. **Name the constraints** — what patterns to follow, what not to break, what
   files are involved, what platform differences matter.
4. **Describe verification** — how does Drew (or the agent) confirm it works?
   List the test scenarios, not the implementation steps.
5. **Skip the code** — don't write find/replace blocks or exact Swift code unless
   the directive involves a specific algorithm, API contract, or data format that
   the agent couldn't infer from the codebase. The agent can read the project and
   write idiomatic Swift that fits the existing patterns.

### Tier 1 — Goal Only (routine features, UI tweaks)
> "Add a button to export the current chat as a markdown file."

The agent explores the project, finds patterns, builds, previews, iterates.
Use for anything where the codebase already has clear patterns to follow.

### Tier 2 — Goal + Constraints + Verification (the default tier)
> "Add a three-dot context menu to each chat row in the sidebar. Include Rename
> (functional — update chatId in SwiftData), Star and Add to Project (show
> 'Under Construction' alert), and Delete (reuse existing deleteChat). Don't
> show Delete or Rename on the Scratch Pad. Keep existing swipe-to-delete.
> Follow existing alert patterns in ContentView."

This is the sweet spot for most work. Drew's engineering judgment steers the
design; the agent handles implementation. Include the *what*, *where*, *why*,
and *what to verify* — not the *how*.

### Tier 3 — Architectural Specification (novel systems only)
Use only when introducing entirely new subsystems, protocols, API integrations,
or patterns that don't yet exist anywhere in the codebase. Even here, describe
the *design and architecture* (data flow, API contracts, type structures) and
let the agent handle the build-error-fix cycle. Don't write the implementation.

Examples that warrant Tier 3: adding the tool-calling loop for the first time,
introducing CloudKit sync, designing a new embedded marker pattern. These need
architectural decisions documented because the agent has no existing pattern to
follow.

---

## Architectural Principles

1. **Orthopraxy informing orthodoxy** — Build abstractions from concrete
   implementations rather than theorizing. Let the doing teach the right design.
2. **Fail fast** — Surface errors immediately, don't mask them.
3. **Zero external dependencies** — Apple frameworks + direct HTTP only. No SPM
   packages, no CocoaPods, no third-party libs.
4. **Separation of concerns for tools** — ToolService owns tool logic;
   ClaudeService owns API communication. Neither reaches into the other.
5. **CloudKit compatibility first** — All SwiftData models must remain safe:
   no `.unique`, all defaults, optional relationships, app-level deduplication.
6. **Manual version tracking** — Bump `AppConfig.buildVersion` before any
   SwiftData schema change, deploy to ALL devices before making the change.

---

## CPB: Commit / Push / Brief

Every meaningful work session ends with CPB — a three-step close-out,
**always in this order**:

1. **Brief** — Update this CLAUDE.md to reflect the current state of the app.
2. **Commit** — Git commit with a clear message describing what changed.
3. **Push** — Push to remote.

Brief comes first so the CLAUDE.md update is captured in the commit.

These are **explicit commands from Drew** — nothing happens automatically.
Drew issues one of four commands: `commit`, `push`, `brief`, or `cpb` (all three).

### Who Can Do What

| Command    | Claude.ai (design/planning) | Xcode Agent (implementation) |
|------------|----------------------------|------------------------------|
| **Commit** | ✗ — not available           | ✓ via terminal               |
| **Push**   | ✗ — not available           | ✓ via terminal               |
| **Brief**  | ✓ direct file edit          | ✓ direct file edit           |
| **CPB**    | Brief only (no git)         | ✓ all three                  |

Claude.ai handles upstream design and documentation. Git operations stay
with the Xcode agent or Drew's terminal.

### Why Brief Matters

CLAUDE.md is the bridge between sessions and between interfaces. When the
Xcode agent finishes a build session, its Brief is how Claude.ai picks up
the thread next time. When Claude.ai finishes a design session, its Brief
is how the Xcode agent knows what to build. Without the Brief, Drew becomes
the messenger between them.

The Brief updates the *present tense* picture of the app — not a changelog
(git handles history). It answers: what exists, how it works, and why.

### What to Brief

- **Architecture changes**: New services, protocols, data models, or major
  refactors. Update the architecture diagram and "How the Pieces Work" sections.
- **New capabilities**: Tools added, UI sections introduced, new targets or
  entitlements. Update the relevant sections.
- **Design decisions**: If a meaningful "why" was decided during the session
  (e.g., "we chose X over Y because..."), capture it in Architectural Principles
  or inline where it belongs.
- **In-progress work**: Update "What's In Progress" to reflect current state —
  what's been started, what's next, what's blocked.
- **File changes**: If files were added, renamed, or removed, update the Files
  Reference.

### What NOT to Brief

- Bug fixes, typo corrections, minor UI tweaks — these are git's job.
- Step-by-step accounts of what happened during the session.
- Anything that reads like a changelog entry.

---

## Coding Conventions

- SwiftUI with declarative patterns
- Prefer `async/await` with structured concurrency
- Use `@Observable` / `@Environment` over older `@ObservedObject` patterns
- Error handling: surface to the user via `errorMessage` state, print to console
- API services: streaming via URLSession byte streams with SSE parsing
- Keep views focused — extract subviews when a view exceeds ~100 lines
- Comments: explain *why*, not *what*
- Enums as namespaces for stateless services (ToolService, KeychainService)
- NotificationCenter for macOS menu command → view state communication
- Emoji as visual role indicators (🧠 assistant, 😎 user) — Drew's preference

---

## Environment

- Mac Studio M2 Max, 64GB RAM, macOS Sequoia
- Targets: macOS (primary dev), iOS, iPadOS (via universal app)
- Xcode (current release)
- Always use `python3` (not `python`) for any Python commands
- Git for version control (history captures all implementation details)
- Paid Apple Developer account, iCloud container active

---

## Files Reference

```
mac-claude-chat/
├── CLAUDE.md                          ← you are here
├── directives/                        ← historical cascade directives (context only)
├── mac-claude-chat/
│   ├── mac_claude_chatApp.swift       ← @main, WindowGroup, menu commands
│   ├── ContentView.swift              ← all UI + tool loop + message sending
│   ├── ClaudeService.swift            ← streaming HTTP to Anthropic API
│   ├── ToolService.swift              ← tool definitions, dispatch, ToolResult, WeatherData, HourlyForecast
│   ├── SwiftDataService.swift         ← CRUD + rename + CloudKit deduplication
│   ├── KeychainService.swift          ← secure API key storage + env fallback
│   ├── Models.swift                   ← SwiftData models + in-memory types + ClaudeModel enum
│   ├── APIKeySetupView.swift          ← settings sheet for all API keys
│   ├── mac-claude-chat.entitlements   ← keychain, iCloud, CloudKit, push
│   └── Assets.xcassets/               ← app icon and colors
├── mac-claude-chat.xcodeproj/
├── mac-claude-chatTests/
└── mac-claude-chatUITests/
```

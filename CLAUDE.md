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
│  ContentView.swift (~950 lines)                  │
│  The entire UI lives here:                       │
│  - NavigationSplitView (sidebar + detail)        │
│  - Chat list management                          │
│  - Message display with streaming                │
│  - Input bar with model selector                 │
│  - Tool activity indicators                      │
│  - The agentic tool loop (sendMessage)           │
│  Also contains: MessageBubble, MarkdownMessage,  │
│  CodeBlockView, WeatherCardView                  │
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
  variants), daily high/low, and a `[HourlyForecast]` array (next 6 hours with
  per-hour temp, conditions, icon code, and precipitation probability).

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
  activity indicators. Input bar at bottom with scrollable text field (max 200pt
  height), model selector dropdown, token count, cost estimate, and Clear Chat.

Message rendering handles markdown (via `AttributedString(markdown:)`) and
fenced code blocks (extracted by a custom parser, displayed in monospaced font
with language labels and horizontal scrolling). Rich tool results (like weather)
render as inline cards above Claude's prose response.

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
- **One Call API 3.0 + hourly forecast** — Weather tool uses OWM One Call 3.0,
  returning current conditions, daily high/low, and 6-hour forecast in a
  single API call. WeatherCardView displays all this: current temp with
  high/low, weather icon (day/night variants via icon code mapping), and
  a horizontal hourly row showing hour label, condition icon, precipitation
  % (with droplet icon), and temperature (°F).
- **Rich weather cards** — Weather tool results display as visual cards with
  SF Symbol icons, temperature, conditions, and details. The embedded marker
  pattern enables this without SwiftData schema changes.
- **Cleaner UI** — Gemini-inspired layout with unbubbled assistant messages,
  softer user bubbles, constrained content width, and more breathing room.

Areas open for development:
- **Rich search results** — Apply the same marker pattern to web search for
  card-based result display.
- **Apple platform integration** — Shortcuts, widgets, Siri.

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

When handing work to the Xcode Claude Agent, match directive detail to complexity:

### Tier 1 — Goal Only (routine features, UI tweaks)
> "Add a button to export the current chat as a markdown file."

The agent explores the project, finds patterns, builds, previews, iterates.

### Tier 2 — Goal + Constraints (features with architectural opinions)
> "Add a chat export button in the header bar next to the model selector.
> Use NSSavePanel on macOS. Format messages with emoji role indicators
> (🧠/😎) matching the existing MessageBubble style. Include token counts
> and cost in a footer."

Drew's engineering judgment steers *where things go* and *what patterns to follow*.

### Tier 3 — Detailed Specification (novel architecture, complex systems)
> See `directives/` folder for examples. Use when introducing new subsystems,
> protocols, or patterns that don't yet exist in the codebase. Even here,
> describe the *design* and let the agent handle the build-error-fix cycle.

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

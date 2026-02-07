# Transition: Multi-Provider LLM Architecture for mac-claude-chat

## Context
We're adding multi-provider support to the native macOS/iOS SwiftUI chat app `mac-claude-chat` at `/Users/drew/.projects/mac-claude-chat`. The app currently works with Claude only via `ClaudeService.swift` with full streaming and tool calling support.

## Philosophy
"Orthopraxy informing orthodoxy" — build the abstraction from two concrete implementations (Claude + xAI/Grok) rather than theorizing about six providers. Let the doing teach us the right design.

## Current State

### What Exists
- **ClaudeService.swift** — Two streaming methods:
  1. `streamMessage()` — simple text streaming with `onChunk`/`onComplete` callbacks
  2. `streamMessageWithTools()` — full tool-aware streaming returning `StreamResult` with text, tool calls, stop reason, tokens
- **ToolService.swift** — Provider-independent tool execution:
  - `get_datetime` (always available)
  - `search_web` via Tavily API (conditional on key)
  - `get_weather` via OpenWeatherMap (conditional on key)
  - Tool definitions are in Claude's JSON format (`input_schema`)
  - Tool execution is generic (just functions returning strings)
- **KeychainService** — stores API keys (Anthropic, Tavily, OWM)
- **Models.swift** — SwiftData models (CloudKit-compatible) for ChatSession/ChatMessage
- **ContentView.swift** — Main UI with chat list, message view, streaming display

### CloudKit Sync (just implemented)
- All models CloudKit-compatible (no `.unique`, all defaults, optional relationships)
- Deduplication logic for multi-device race conditions
- Paid Apple Developer account active, iCloud container registered

## Design Decision: xAI/Grok as Second Provider

### Why xAI
- Drew's preference (likes Elon, dislikes OpenAI head, finds Gemini's "free" model predatory)
- OpenAI-compatible REST API — patterns will transfer to other OpenAI-compatible providers (Mistral, Groq, etc.)
- Good stress test: similar enough to reveal subtle differences, different enough to find real abstraction seams

### xAI API Key Facts (from research)
- **Base URL**: `https://api.x.ai/v1/chat/completions` (OpenAI-compatible)
- **Auth**: `Authorization: Bearer <XAI_API_KEY>` (not custom header like Claude's `x-api-key`)
- **Current models**: `grok-4`, `grok-4-fast`, `grok-4-1-fast-reasoning`, `grok-4-1-fast-non-reasoning`
- **Streaming**: SSE format, OpenAI-compatible (`"stream": true`)
- **Tool calling**: OpenAI-compatible format:
  - Tools defined with `"type": "function"`, `"function": { "name", "description", "parameters" }`
  - Tool calls returned in `choices[0].message.tool_calls` array
  - Each tool call has `id`, `function.name`, `function.arguments` (JSON string)
  - Tool results sent as `{"role": "tool", "tool_call_id": "...", "content": "..."}`
- **Key differences from Claude**:
  - System prompt goes in `messages` array as `{"role": "system", ...}` not separate field
  - Tool definitions use `"parameters"` not `"input_schema"`
  - Tool calls come in `choices[0].message.tool_calls` not as content blocks
  - Tool results use role `"tool"` with `tool_call_id`, not `"user"` with `tool_result` content blocks
  - Token usage in `usage.prompt_tokens`/`usage.completion_tokens` (not `input_tokens`/`output_tokens`)
  - Stop reason in `choices[0].finish_reason` not top-level `stop_reason`
- **Note**: xAI also has a newer "Responses API" (stateful, server-side tools) but we should use Chat Completions for parity with our Claude implementation

## Proposed Architecture (to be refined by building)

### LLMProvider Protocol (Swift)
```swift
protocol LLMProvider {
    var id: String { get }           // "claude", "xai"
    var displayName: String { get }  // "Claude", "Grok"
    var hasAPIKey: Bool { get }
    var availableModels: [LLMModel] { get }
    
    func streamMessage(
        messages: [ProviderMessage],
        model: LLMModel,
        systemPrompt: String,
        tools: [ToolDefinition]?,
        onTextChunk: @escaping (String) -> Void
    ) async throws -> StreamResult
}
```

### Key Abstraction Points
1. **Message format** — normalize to/from provider-specific formats
2. **Tool definitions** — translate from canonical format to Claude's `input_schema` vs OpenAI's `parameters`
3. **Tool call/result wire format** — different content block structures
4. **Token counting** — different field names but same concept
5. **Auth** — different header patterns
6. **ToolService stays unchanged** — execution is provider-independent, only definitions and wire format change

### What NOT to Abstract (yet)
- Provider-specific features (extended thinking, citations, reasoning tokens)
- Server-side tools (xAI's Responses API, Claude's built-in tools)
- Image/multimodal input differences

## Next Steps
1. Read current ClaudeService.swift and ToolService.swift (reference above)
2. Define the `LLMProvider` protocol based on what ClaudeService actually does
3. Refactor ClaudeService to conform to the protocol
4. Build XAIService conforming to same protocol
5. Add xAI API key storage to KeychainService
6. Add provider selection UI (Settings + per-chat)
7. Update ContentView to use provider-agnostic interface

## Files to Reference
- `/Users/drew/.projects/mac-claude-chat/mac-claude-chat/ClaudeService.swift`
- `/Users/drew/.projects/mac-claude-chat/mac-claude-chat/ToolService.swift`
- `/Users/drew/.projects/mac-claude-chat/mac-claude-chat/KeychainService.swift`
- `/Users/drew/.projects/mac-claude-chat/mac-claude-chat/Models.swift`
- `/Users/drew/.projects/mac-claude-chat/mac-claude-chat/ContentView.swift`
- `/Users/drew/.projects/mac-claude-chat/mac-claude-chat/mac-claude-chat.entitlements`

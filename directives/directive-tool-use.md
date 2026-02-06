# Directive: Add Tool Use to mac-claude-chat

## Project Context

**App:** mac-claude-chat — Native macOS SwiftUI chat application  
**Location:** `/Users/drew/.projects/mac-claude-chat/`  
**Current State:** Working app with SwiftData persistence, streaming API responses, model selection (Haiku/Sonnet/Opus), markdown rendering. No tool support yet.  
**Goal:** Add custom client tool calling with Tavily web search, OpenWeatherMap weather, and local datetime. Establish the pattern for all three tool types (native Anthropic, custom client, MCP remote) for future reuse.

---

## Architecture Overview: Three Types of Tool Use

The Claude Messages API supports three categories of tools. This app will implement **Type 2 (Custom Client Tools)** now, with architecture prepared for Types 1 and 3 later.

### Type 1: Anthropic-Managed Tools (Future)
Server-side tools Anthropic hosts. You declare them, Claude executes them internally.
```json
{"type": "web_search_20250305", "name": "web_search", "max_uses": 5}
```
Cost: $10/1,000 searches + token costs for ingested results. No client-side execution needed.

### Type 2: Custom Client Tools (This Directive)
You define the schema, Claude requests execution, YOUR CODE runs the tool locally, you send results back. This is the pattern used in all of Drew's Python chat apps.
```json
{
  "name": "search_web",
  "description": "Search the web...",
  "input_schema": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}
}
```

### Type 3: MCP Remote Tools (Future)
Model Context Protocol servers. The API has an MCP Connector that routes to remote tool servers. Requires `anthropic-beta: mcp-client-2025-04-04` header.

---

## Reference Implementation

Drew's Python apps (`claude-st-chat` and `xai-st-chat`) implement this exact pattern. The key files:

- **`ai_agent.py`** — Tool definitions, tool loop (max 5 iterations), dispatch dictionary
- **`my_tools.py`** — Tool implementations (Tavily search, OpenWeatherMap, datetime, USDA nutrition)
- **`config.py`** — System prompts with conversational approach and tool guidance

The Swift implementation follows the same architecture translated to native Swift patterns.

---

## Phase 1: API Layer Changes (ClaudeService)

### 1.1 New Codable Types for Tool Use

The current `ClaudeAPIRequest` sends `messages` as simple `[ClaudeMessage]` with string content. Tool use requires structured content blocks. Add these types:

```swift
// MARK: - Tool Use Types

/// Tool definition sent in API request
struct ToolDefinition: Codable {
    let name: String
    let description: String
    let input_schema: JSONSchema
}

/// JSON Schema for tool input
struct JSONSchema: Codable {
    let type: String
    let properties: [String: PropertySchema]?
    let required: [String]?
}

struct PropertySchema: Codable {
    let type: String
    let description: String?
}

/// A content block in Claude's response (text or tool_use)
enum ResponseContentBlock {
    case text(String)
    case toolUse(id: String, name: String, input: [String: Any])
}

/// Tool result sent back to Claude
struct ToolResultContent: Codable {
    let type: String  // "tool_result"
    let tool_use_id: String
    let content: String
}
```

### 1.2 Updated Request Structure

Replace `ClaudeAPIRequest` with a version that supports tools:

```swift
struct ClaudeAPIRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [[String: Any]]  // Must support mixed content types
    let stream: Bool
    let tools: [ToolDefinition]?
    
    // Custom encoding needed because messages contain heterogeneous content
}
```

**Critical insight:** When Claude responds with tool_use, the assistant message contains structured content blocks (both text and tool_use blocks). When sending tool results back, the user message contains `tool_result` blocks. These CANNOT be simple `{"role": "user", "content": "string"}` — they must be `{"role": "user", "content": [array of blocks]}`.

### 1.3 Updated Streaming Handler

The current `streamMessage` function streams until completion. With tools, the stream may end with `stop_reason: "tool_use"` instead of `"end_turn"`. The function must:

1. Detect `stop_reason` from `message_delta` events
2. Collect `content_block_start` events of type `tool_use` (these contain tool name and ID)
3. Collect `content_block_delta` events of type `input_json_delta` (these accumulate the tool input JSON)
4. Return the stop reason so the caller knows whether to execute tools and loop

**New streaming event types to handle:**

```
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_xxx","name":"search_web","input":{}}}

event: content_block_delta  
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"..."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},...}
```

**Revised `streamMessage` signature:**

```swift
struct StreamResult {
    var textContent: String
    var toolCalls: [ToolCall]
    var stopReason: String  // "end_turn" or "tool_use"
    var inputTokens: Int
    var outputTokens: Int
}

struct ToolCall {
    let id: String
    let name: String
    let input: [String: Any]
}

func streamMessage(
    messages: [[String: Any]],  // Structured messages supporting tool results
    model: ClaudeModel,
    systemPrompt: String,
    tools: [ToolDefinition]?,
    onTextChunk: @escaping (String) -> Void,
    onToolStart: @escaping (String) -> Void  // Called when tool use begins, for UI feedback
) async throws -> StreamResult
```

### 1.4 The Tool Loop

In `sendMessage()`, replace the single API call with a loop:

```
1. Build messages array from conversation history
2. Call streamMessage with tools
3. If stopReason == "end_turn" → done, save assistant message
4. If stopReason == "tool_use":
   a. Show "🔧 Using tool: {name}" in UI
   b. Execute each tool call locally (Tavily HTTP, weather HTTP, Date())
   c. Append assistant's response (with tool_use blocks) to messages
   d. Append tool_result messages to messages  
   e. Go to step 2 (max 5 iterations)
5. Save the final text response as the assistant message
```

---

## Phase 2: Tool Implementations (ToolService)

Create a new file: `ToolService.swift`

### 2.1 Tavily Web Search

Simple HTTP POST. No SDK needed — it's just a REST API.

```
POST https://api.tavily.com/search
Content-Type: application/json

{
  "api_key": "tvly-xxxxx",
  "query": "Baltimore Ravens score today",
  "search_depth": "advanced",
  "include_answer": true,
  "max_results": 6
}
```

Response is JSON with `answer` (AI summary) and `results` array with `title`, `url`, `content` for each result.

**API key:** Store in Keychain alongside the Anthropic key, or use environment variable `TAVILY_API_KEY`. Drew already has a Tavily account with 1,000 free credits/month.

Format tool results the same way as the Python app:
```
[Summary] AI-generated answer...

[1] Title
URL: https://...
Content snippet...

[2] Title  
URL: https://...
Content snippet...
```

### 2.2 OpenWeatherMap Weather

Two HTTP GETs — geocode then weather. Same pattern as Python `my_tools.py`.

```
GET https://api.openweathermap.org/geo/1.0/direct?q={location}&limit=1&appid={key}
GET https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={key}&units=imperial
```

**API key:** Environment variable `OWM_API_KEY` or Keychain.

Default location: Catonsville, Maryland (when location parameter is empty/null).

### 2.3 Date/Time

Trivial — just `Date()` formatted for Eastern time:

```swift
func getDateTime() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy h:mm a"
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    return "Current date and time: \(formatter.string(from: Date())) (EST/EDT)"
}
```

### 2.4 Tool Definitions Array

```swift
static let toolDefinitions: [ToolDefinition] = [
    ToolDefinition(
        name: "search_web",
        description: "Search the web for current information on any topic. Use this when you need up-to-date information about news, sports, current events, or any topic that changes frequently. Don't deflect with 'I don't have real-time data' — search for it.",
        input_schema: JSONSchema(
            type: "object",
            properties: [
                "query": PropertySchema(type: "string", description: "The search query. Be specific and include relevant context.")
            ],
            required: ["query"]
        )
    ),
    ToolDefinition(
        name: "get_weather",
        description: "Get current weather information for a specific location. Can handle cities, states, or full addresses. Defaults to user's location (Catonsville, Maryland) if no location specified.",
        input_schema: JSONSchema(
            type: "object",
            properties: [
                "location": PropertySchema(type: "string", description: "The location to get weather for (city, state, country). If empty, uses user's default location.")
            ],
            required: ["location"]
        )
    ),
    ToolDefinition(
        name: "get_datetime",
        description: "Get the current date and time in the user's timezone. Use this when you need to know what time it is now.",
        input_schema: JSONSchema(
            type: "object",
            properties: nil,
            required: []
        )
    )
]
```

### 2.5 Tool Dispatch

```swift
func executeTool(name: String, input: [String: Any]) async -> String {
    switch name {
    case "search_web":
        let query = input["query"] as? String ?? ""
        return await searchWeb(query: query)
    case "get_weather":
        let location = input["location"] as? String ?? ""
        return await getWeather(location: location)
    case "get_datetime":
        return getDateTime()
    default:
        return "Unknown tool: \(name)"
    }
}
```

---

## Phase 3: System Prompt Upgrade

The current system prompt is a single line:
```
"You are Claude, a conversational AI assistant chatting with Drew..."
```

Replace with a proper conversational prompt modeled on the xai-st-chat pattern. This is **critical** for good tool-calling behavior:

```swift
static let systemPrompt = """
You are Claude, an AI assistant engaged in a natural conversation with Drew. You're not just an assistant — you're a conversational partner who thinks, reacts, and builds on what's been discussed.

CONVERSATIONAL APPROACH:
- This is a real conversation, not a series of isolated requests and responses
- When you ask questions, you genuinely want to hear Drew's thoughts and will build on them
- Pay attention to conversational flow — reference what's been discussed, acknowledge responses
- Feel free to express curiosity, surprise, agreement, or thoughtful disagreement

USER CONTEXT:
- User: Andrew Killeen (prefers to be called Drew)
- Location: Catonsville, Maryland, USA
- Timezone: EST/EDT
- Background: Retired engineer and programmer, 54 years of coding experience
- Interests: Programming (Python, Swift), AI, gardening, weather

TOOL USAGE:
You have tool calling capabilities. Use your tools confidently:
- search_web: For current information (sports, news, events, research, anything that changes)
- get_weather: For weather information (defaults to Drew's location if unspecified)
- get_datetime: Get current date and time in Drew's timezone

Don't deflect with "I don't have real-time data" — search for it.
For weather queries, use current conditions for Drew's area by default.
Provide current, complete answers rather than directing the user elsewhere.
Use the get_datetime tool when you need to know what day or time it is.
You can call multiple tools when needed.

CONVERSATION MEMORY:
- Remember what Drew has shared and what you've discussed in this chat
- When you ask something, actually listen to and build on the response
- Reference earlier parts of your conversation when relevant

Be genuine, thoughtful, and conversational.
"""
```

---

## Phase 4: UI Enhancements

### 4.1 Tool Activity Indicator

When Claude is executing tools, show a visual indicator instead of just the spinner:

```
🔧 Searching the web for "Ravens score today"...
```

Use the `onToolStart` callback from the stream to update a `@State var toolActivity: String?` that displays in the streaming area.

### 4.2 API Key Management

Add Tavily API key to the existing `KeychainService` and `APIKeySetupView`:
- New Keychain key: `com.mac-claude-chat.tavily-api-key`
- Add a second field in the setup view (optional — tools work without it, just no web search)
- Fall back to `TAVILY_API_KEY` environment variable
- Similarly for `OWM_API_KEY` (OpenWeatherMap)

### 4.3 App Sandbox Entitlements

The app already has `com.apple.security.network.client = true` (outgoing connections). This covers Tavily and OpenWeatherMap API calls. No changes needed.

---

## Phase 5: Message History Format for Tool Conversations

This is the trickiest part. When tool calls happen mid-conversation, the message history sent to Claude on subsequent turns must include the full tool exchange. The messages array for a conversation with tools looks like:

```json
[
  {"role": "user", "content": "What's the weather like?"},
  {"role": "assistant", "content": [
    {"type": "text", "text": "Let me check the weather for you."},
    {"type": "tool_use", "id": "toolu_abc", "name": "get_weather", "input": {"location": "Catonsville, Maryland"}}
  ]},
  {"role": "user", "content": [
    {"type": "tool_result", "tool_use_id": "toolu_abc", "content": "Current Weather for Catonsville:\n• Conditions: Partly Cloudy\n• Temperature: 42°F..."}
  ]},
  {"role": "assistant", "content": "It's 42°F and partly cloudy in Catonsville right now..."}
]
```

**Key design decision:** The saved `Message` objects in SwiftData store only the final text. The intermediate tool_use/tool_result exchanges are ephemeral — they exist only during the active API call loop and are NOT persisted. This matches the Python app behavior. On reload, the conversation shows user message → assistant's final text response, with the tool mechanics invisible.

However, for the CURRENT turn's API call, the full structured messages (including tool exchanges from THIS turn) must be maintained in a local `var apiMessages: [[String: Any]]` array during the tool loop.

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `ToolService.swift` | **NEW** | Tool definitions, dispatch, Tavily/weather/datetime implementations |
| `ContentView.swift` | **MODIFY** | Updated sendMessage() with tool loop, tool activity UI, system prompt |
| `ClaudeService` (in ContentView) | **MODIFY** | New streaming types, structured message support, tool-aware streaming |
| `KeychainService.swift` | **MODIFY** | Add Tavily/OWM key storage methods |
| `APIKeySetupView.swift` | **MODIFY** | Add optional Tavily/OWM key fields |

---

## Testing Checklist

After implementation, test these scenarios:

1. **No-tool message:** "What is the capital of France?" → Should respond normally without tools
2. **Web search:** "What's the latest Ravens news?" → Should trigger search_web, show tool activity, return results
3. **Weather (default):** "What's the weather?" → Should trigger get_weather with Catonsville default
4. **Weather (custom):** "What's the weather in San Francisco?" → Should pass "San Francisco" to get_weather
5. **DateTime:** "What day is it?" → Should trigger get_datetime
6. **Multi-tool:** "What's the weather and what time is it?" → Should call both tools
7. **Tool loop:** "Search for X and then search for Y based on those results" → Multiple iterations
8. **No API key:** Tavily key missing → search_web returns error message, Claude explains gracefully
9. **Streaming:** Text should stream normally between tool calls
10. **History:** After tool-assisted response, next message should work normally (tool exchanges NOT in persisted history)

---

## Important Implementation Notes

1. **JSON encoding for mixed-type messages:** Swift's `Codable` struggles with the heterogeneous `content` field (sometimes a string, sometimes an array of typed blocks). Use `JSONSerialization` to build the request body manually rather than fighting `Codable` for this specific case.

2. **Tool input accumulation during streaming:** The `input_json_delta` events send partial JSON chunks. Accumulate them into a string, then parse the complete JSON when `content_block_stop` fires.

3. **Error handling in tools:** If a tool HTTP call fails, return the error as the tool result string. Claude will gracefully explain the failure to the user. Never throw from tool execution.

4. **Token counting with tools:** The `message_start` event gives input tokens. The `message_delta` event gives output tokens. In a multi-iteration tool loop, accumulate tokens across ALL iterations for accurate cost tracking.

5. **Max iterations safety:** Cap at 5 iterations (matching the Python apps). If exceeded, take whatever text Claude has produced and present it as the response.

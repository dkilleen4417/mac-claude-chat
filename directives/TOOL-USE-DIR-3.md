# DIR-3: Add Tool-Aware Streaming to ClaudeService

## Objective
Add a new `streamMessageWithTools()` method to `ClaudeService` that handles tool-aware streaming — parsing `content_block_start` for tool_use blocks, accumulating `input_json_delta` chunks, and returning a `StreamResult` with text content, tool calls, and stop reason. The existing `streamMessage()` remains untouched for now. App compiles and runs with no behavioral change.

## Prerequisites
- DIR-2 completed (ToolService.swift and StreamResult/ToolCall types exist)

## Instructions

### Step 1: Add streamMessageWithTools to ClaudeService
**File**: `mac-claude-chat/ContentView.swift`
**Location**: Inside the `ClaudeService` class, after the closing brace of the existing `streamMessage()` method
**Action**: Add new method

**Find this code** (the end of the existing `streamMessage` method):
```swift
        await MainActor.run {
            onComplete(inputTokens, outputTokens)
        }
    }
}
```

**Add after the closing brace of `streamMessage` (but still inside the `ClaudeService` class)**:

```swift

    /// Tool-aware streaming that handles text and tool_use content blocks.
    /// Returns a StreamResult with accumulated text, parsed tool calls, and stop reason.
    /// The caller is responsible for the tool execution loop.
    func streamMessageWithTools(
        messages: [[String: Any]],
        model: ClaudeModel,
        systemPrompt: String,
        tools: [[String: Any]]?,
        onTextChunk: @escaping (String) -> Void
    ) async throws -> StreamResult {
        guard let apiKey = apiKey else {
            throw NSError(domain: "ClaudeAPI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No API key configured. Please add your Anthropic API key in Settings."])
        }

        // Build request body with JSONSerialization (required for polymorphic content field)
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 8192,
            "system": systemPrompt,
            "messages": messages,
            "stream": true
        ]
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Read error body for diagnostics
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw NSError(domain: "ClaudeAPI", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorBody)"])
        }

        // Streaming state
        var inputTokens = 0
        var outputTokens = 0
        var textContent = ""
        var toolCalls: [ToolCall] = []
        var stopReason = "end_turn"

        // Current content block tracking
        var currentBlockType: String?
        var currentToolId: String?
        var currentToolName: String?
        var currentToolInputJson = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard jsonString != "[DONE]",
                  let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventType = json["type"] as? String
            else { continue }

            switch eventType {
            case "message_start":
                if let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any],
                   let input = usage["input_tokens"] as? Int {
                    inputTokens = input
                }

            case "content_block_start":
                if let contentBlock = json["content_block"] as? [String: Any],
                   let blockType = contentBlock["type"] as? String {
                    currentBlockType = blockType
                    if blockType == "tool_use" {
                        currentToolId = contentBlock["id"] as? String
                        currentToolName = contentBlock["name"] as? String
                        currentToolInputJson = ""
                    }
                }

            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let deltaType = delta["type"] as? String {
                    switch deltaType {
                    case "text_delta":
                        if let text = delta["text"] as? String {
                            textContent += text
                            await MainActor.run { onTextChunk(text) }
                        }
                    case "input_json_delta":
                        if let partialJson = delta["partial_json"] as? String {
                            currentToolInputJson += partialJson
                        }
                    default:
                        break
                    }
                }

            case "content_block_stop":
                if currentBlockType == "tool_use",
                   let toolId = currentToolId,
                   let toolName = currentToolName {
                    // Parse the accumulated JSON input
                    let parsedInput: [String: Any]
                    if let jsonData = currentToolInputJson.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        parsedInput = parsed
                    } else {
                        parsedInput = [:]
                    }
                    toolCalls.append(ToolCall(id: toolId, name: toolName, input: parsedInput))
                }
                // Reset block tracking
                currentBlockType = nil
                currentToolId = nil
                currentToolName = nil
                currentToolInputJson = ""

            case "message_delta":
                if let delta = json["delta"] as? [String: Any],
                   let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }
                if let usage = json["usage"] as? [String: Any],
                   let output = usage["output_tokens"] as? Int {
                    outputTokens = output
                }

            default:
                break
            }
        }

        return StreamResult(
            textContent: textContent,
            toolCalls: toolCalls,
            stopReason: stopReason,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
```

**Important**: The method goes inside the `ClaudeService` class — between the closing `}` of `streamMessage()` and the closing `}` of the class. Verify the final brace structure is:

```swift
class ClaudeService {
    // ... properties ...

    func streamMessage(...) async throws {
        // ... existing code ...
    }

    func streamMessageWithTools(...) async throws -> StreamResult {
        // ... new code ...
    }
}
```

## Verification
1. Build the app — should compile with zero errors
2. Run the app, send a message — existing streaming works exactly as before (still uses old `streamMessage`)
3. The new method exists but is not yet called

## Checkpoint
- [ ] App compiles without errors
- [ ] Chat works exactly as before (old streamMessage still in use)
- [ ] No runtime changes

# DIR-4: Wire Up Tool Loop, System Prompt, and UI Indicator

## Objective
Replace `sendMessage()` with a tool-aware version that uses `streamMessageWithTools`, executes tools via `ToolService`, loops up to 5 iterations, and shows tool activity in the UI. Add the conversational system prompt. This is the activation directive — after this, tools are live.

## Prerequisites
- DIR-1 completed (KeychainService has tool key methods)
- DIR-2 completed (ToolService.swift exists with definitions, dispatch, and implementations)
- DIR-3 completed (ClaudeService has `streamMessageWithTools()` method)

## Instructions

### Step 1: Add Tool Activity State Variable
**File**: `mac-claude-chat/ContentView.swift`
**Location**: In the `ContentView` struct's state variables block

**Find this code**:
```swift
    @State private var showingAPIKeySetup: Bool = false
    @State private var needsAPIKey: Bool = false
```

**Replace with**:
```swift
    @State private var showingAPIKeySetup: Bool = false
    @State private var needsAPIKey: Bool = false
    @State private var toolActivityMessage: String?
```

### Step 2: Add System Prompt Property
**File**: `mac-claude-chat/ContentView.swift`
**Location**: Inside `ContentView`, after the `dataService` computed property

**Find this code**:
```swift
    private var dataService: SwiftDataService {
        SwiftDataService(modelContext: modelContext)
    }
```

**Add immediately after**:
```swift

    private var systemPrompt: String {
        """
        You are Claude, an AI assistant in a natural conversation with Drew \
        (Andrew Killeen), a retired engineer and programmer in Catonsville, Maryland.

        CONVERSATIONAL APPROACH:
        - This is a real conversation, not a series of isolated requests and responses.
        - Build on what's been discussed, reference earlier parts of conversation.
        - Express curiosity, surprise, agreement, or thoughtful disagreement naturally.
        - Be genuine and conversational, not formulaic.

        USER CONTEXT:
        - Name: Drew (Andrew Killeen), prefers "Drew"
        - Location: Catonsville, Maryland (Eastern timezone)
        - Background: 74-year-old retired engineer, 54 years of coding experience
        - Current interests: Python/Streamlit/SwiftUI development, AI applications, gardening, weather

        TOOL USAGE:
        You have tools available — use them confidently:
        - get_datetime: Get current date and time (Eastern timezone)
        - search_web: Search the web for current information (news, sports, events, research)
        - get_weather: Get current weather (defaults to Catonsville, Maryland)
        Don't deflect with "I don't have real-time data" — search for it.
        You can call multiple tools in a single response when needed.
        For weather queries with no specific location, default to Drew's location.
        """
    }
```

### Step 3: Add Tool Activity Indicator to UI
**File**: `mac-claude-chat/ContentView.swift`
**Location**: In the `chatView` body, inside the `ScrollView`'s `VStack`, between the streaming content block and the loading spinner

**Find this code**:
```swift
                            if let streamingId = streamingMessageId, !streamingContent.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("🧠")
                                        .font(.title2)
                                    
                                    MarkdownMessageView(content: streamingContent)
                                    
                                    Spacer()
                                }
                                .id(streamingId)
                            }
                            
                            if isLoading && streamingContent.isEmpty {
```

**Replace with**:
```swift
                            if let streamingId = streamingMessageId, !streamingContent.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("🧠")
                                        .font(.title2)
                                    
                                    MarkdownMessageView(content: streamingContent)
                                    
                                    Spacer()
                                }
                                .id(streamingId)
                            }
                            
                            if let toolMessage = toolActivityMessage {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(toolMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                    Spacer()
                                }
                                .padding(.leading, 36)
                            }
                            
                            if isLoading && streamingContent.isEmpty && toolActivityMessage == nil {
```

**Note**: The spinner condition now also checks `toolActivityMessage == nil` to avoid showing both the spinner and the tool indicator simultaneously.

### Step 4: Replace sendMessage() with Tool-Aware Version
**File**: `mac-claude-chat/ContentView.swift`
**Location**: The entire `sendMessage()` method in the `// MARK: - Message Sending` section

**Find this code** (the entire sendMessage method):
```swift
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let chatId = selectedChat else { return }
        
        let userMessage = Message(
            role: .user,
            content: messageText,
            timestamp: Date()
        )
        
        messages.append(userMessage)
        
        do {
            try dataService.saveMessage(userMessage, chatId: chatId)
        } catch {
            print("Failed to save user message: \(error)")
        }
        
        messageText = ""
        errorMessage = nil
        
        let assistantMessageId = UUID()
        streamingMessageId = assistantMessageId
        streamingContent = ""
        isLoading = true
        
        Task {
            do {
                var fullResponse = ""
                var streamInputTokens = 0
                var streamOutputTokens = 0
                
                try await claudeService.streamMessage(
                    messages: messages,
                    model: selectedModel,
                    onChunk: { chunk in
                        streamingContent += chunk
                        fullResponse += chunk
                    },
                    onComplete: { inputTokens, outputTokens in
                        streamInputTokens = inputTokens
                        streamOutputTokens = outputTokens
                    }
                )
                
                totalInputTokens += streamInputTokens
                totalOutputTokens += streamOutputTokens
                
                let assistantMessage = Message(
                    id: assistantMessageId,
                    role: .assistant,
                    content: fullResponse,
                    timestamp: Date()
                )
                
                messages.append(assistantMessage)
                streamingMessageId = nil
                streamingContent = ""
                isLoading = false
                
                try dataService.saveMessage(assistantMessage, chatId: chatId)
                
                let isDefault = chatId == "Scratch Pad"
                try dataService.saveMetadata(
                    chatId: chatId,
                    inputTokens: totalInputTokens,
                    outputTokens: totalOutputTokens,
                    isDefault: isDefault
                )
                
                loadAllChats()
                
            } catch {
                isLoading = false
                streamingMessageId = nil
                streamingContent = ""
                errorMessage = "Error: \(error.localizedDescription)"
                print("Claude API Error: \(error)")
            }
        }
    }
```

**Replace with**:
```swift
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let chatId = selectedChat else { return }

        let userMessage = Message(
            role: .user,
            content: messageText,
            timestamp: Date()
        )

        messages.append(userMessage)

        do {
            try dataService.saveMessage(userMessage, chatId: chatId)
        } catch {
            print("Failed to save user message: \(error)")
        }

        messageText = ""
        errorMessage = nil

        let assistantMessageId = UUID()
        streamingMessageId = assistantMessageId
        streamingContent = ""
        toolActivityMessage = nil
        isLoading = true

        Task {
            do {
                // Build API messages from persisted history (simple string content)
                var apiMessages: [[String: Any]] = messages.map { msg in
                    [
                        "role": msg.role == .user ? "user" : "assistant",
                        "content": msg.content
                    ]
                }

                let tools = ToolService.toolDefinitions
                var fullResponse = ""
                var totalStreamInputTokens = 0
                var totalStreamOutputTokens = 0
                var iteration = 0
                let maxIterations = 5

                // Tool loop: stream, check for tool calls, execute, repeat
                while iteration < maxIterations {
                    iteration += 1

                    let result = try await claudeService.streamMessageWithTools(
                        messages: apiMessages,
                        model: selectedModel,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        onTextChunk: { chunk in
                            streamingContent += chunk
                            fullResponse += chunk
                        }
                    )

                    totalStreamInputTokens += result.inputTokens
                    totalStreamOutputTokens += result.outputTokens

                    // If no tool calls, we're done
                    if result.stopReason == "end_turn" || result.toolCalls.isEmpty {
                        break
                    }

                    // Build the assistant's response as structured content blocks
                    var assistantContent: [[String: Any]] = []
                    if !result.textContent.isEmpty {
                        assistantContent.append(["type": "text", "text": result.textContent])
                    }
                    for toolCall in result.toolCalls {
                        assistantContent.append([
                            "type": "tool_use",
                            "id": toolCall.id,
                            "name": toolCall.name,
                            "input": toolCall.input
                        ])
                    }
                    apiMessages.append(["role": "assistant", "content": assistantContent])

                    // Execute each tool and collect results
                    var toolResults: [[String: Any]] = []
                    for toolCall in result.toolCalls {
                        // Show tool activity in UI
                        let displayName: String
                        switch toolCall.name {
                        case "search_web":
                            let query = toolCall.input["query"] as? String ?? ""
                            displayName = "🔍 Searching: \(query)"
                        case "get_weather":
                            let location = toolCall.input["location"] as? String ?? "Catonsville"
                            displayName = "🌤️ Getting weather for \(location)"
                        case "get_datetime":
                            displayName = "🕐 Checking date/time"
                        default:
                            displayName = "🔧 Using \(toolCall.name)"
                        }
                        await MainActor.run {
                            toolActivityMessage = displayName
                        }

                        let toolResult = await ToolService.executeTool(
                            name: toolCall.name,
                            input: toolCall.input
                        )
                        toolResults.append([
                            "type": "tool_result",
                            "tool_use_id": toolCall.id,
                            "content": toolResult
                        ])
                    }

                    // Add tool results as a user message (Claude API convention)
                    apiMessages.append(["role": "user", "content": toolResults])

                    // Clear tool indicator and add separator for next streaming iteration
                    await MainActor.run {
                        toolActivityMessage = nil
                        if !fullResponse.isEmpty {
                            streamingContent += "\n\n"
                            fullResponse += "\n\n"
                        }
                    }
                }

                // Finalize
                totalInputTokens += totalStreamInputTokens
                totalOutputTokens += totalStreamOutputTokens

                let assistantMessage = Message(
                    id: assistantMessageId,
                    role: .assistant,
                    content: fullResponse,
                    timestamp: Date()
                )

                messages.append(assistantMessage)
                streamingMessageId = nil
                streamingContent = ""
                toolActivityMessage = nil
                isLoading = false

                try dataService.saveMessage(assistantMessage, chatId: chatId)

                let isDefault = chatId == "Scratch Pad"
                try dataService.saveMetadata(
                    chatId: chatId,
                    inputTokens: totalInputTokens,
                    outputTokens: totalOutputTokens,
                    isDefault: isDefault
                )

                loadAllChats()

            } catch {
                isLoading = false
                streamingMessageId = nil
                streamingContent = ""
                toolActivityMessage = nil
                errorMessage = "Error: \(error.localizedDescription)"
                print("Claude API Error: \(error)")
            }
        }
    }
```

## Verification

### Test 1: Normal Chat (No Tools)
1. Send "Hello, how are you?"
2. Expect: Normal streaming response, no tool activity indicator
3. Verify: Message saves to history, token counts update

### Test 2: Web Search
1. Send "What's in the news today?"
2. Expect: Brief text streams, then "🔍 Searching: ..." indicator appears, then results stream
3. Verify: Final saved message includes both preamble and search-based answer

### Test 3: Weather (Default Location)
1. Send "What's the weather like?"
2. Expect: "🌤️ Getting weather for Catonsville" indicator, then weather summary
3. Verify: Temperature, conditions, humidity, wind speed in response

### Test 4: Weather (Custom Location)
1. Send "What's the weather in San Francisco?"
2. Expect: "🌤️ Getting weather for San Francisco" indicator, then SF weather

### Test 5: Date/Time
1. Send "What day is it?"
2. Expect: Claude uses get_datetime tool, responds with current date in Eastern time

### Test 6: Missing Tool Keys
1. Remove Tavily key from Keychain (or never set it)
2. Send "Search for latest AI news"
3. Expect: Claude won't have search_web tool available. It should respond conversationally without the tool (no crash, no error)

### Test 7: Conversation History
1. Have a multi-turn conversation
2. Verify earlier messages still provide context
3. Switch chats and back — messages persist correctly

## Checkpoint
- [ ] App compiles without errors
- [ ] Normal (no-tool) messages stream correctly
- [ ] Web search tool executes and results appear in response
- [ ] Weather tool returns current conditions
- [ ] DateTime tool returns correct Eastern time
- [ ] Tool activity indicator shows during tool execution
- [ ] Token counts accumulate across tool loop iterations
- [ ] Messages save to SwiftData correctly (only final text, no tool mechanics)
- [ ] Cost calculation still works
- [ ] No crash when tool API keys are missing

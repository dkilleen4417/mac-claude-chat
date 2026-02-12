//
//  MessageSendingService.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition.
//  Orchestrates: model routing → context filtering → API streaming → tool loops → response assembly.
//  Reports progress to the caller via callbacks. No UI state ownership.
//

import Foundation

enum MessageSendingService {

    // MARK: - Result Types

    /// Final result after the full send cycle completes.
    struct SendResult {
        let assistantMessage: Message       // The assembled assistant message (with markers, tip, model)
        let totalInputTokens: Int           // Total input tokens across all iterations
        let totalOutputTokens: Int          // Total output tokens across all iterations
        let effectiveModel: ClaudeModel     // Which model actually handled the request
    }

    /// Callbacks for real-time progress during the send cycle.
    struct ProgressCallbacks {
        /// Called on MainActor with each text chunk from the streaming response.
        let onTextChunk: @MainActor (String) -> Void
        /// Called on MainActor when a tool starts executing. Pass nil when tool completes.
        let onToolActivity: @MainActor (String?) -> Void
    }

    // MARK: - Send Orchestration

    /// Execute a full send cycle: route → filter → stream → tool loop → assemble.
    ///
    /// - Parameters:
    ///   - messageForAPI: The user's text to send (after slash command stripping, if any).
    ///   - imagesToSend: Captured pending images for this turn's API call.
    ///   - turnId: UUID string for this conversation turn.
    ///   - assistantMessageId: Pre-generated UUID for the assistant's reply.
    ///   - chatId: The chat session ID.
    ///   - threshold: Context grade threshold at send time.
    ///   - messages: Current in-memory messages (for router tip collection).
    ///   - systemPrompt: The full system prompt string.
    ///   - parseResult: The slash command parse result (for model override detection).
    ///   - originalText: The original trimmed user text (for router classification).
    ///   - claudeService: The API service instance.
    ///   - dataService: The SwiftData service instance.
    ///   - progress: Callbacks for streaming chunks and tool activity.
    /// - Returns: A SendResult with the assembled assistant message and token totals.
    static func send(
        messageForAPI: String,
        imagesToSend: [PendingImage],
        turnId: String,
        assistantMessageId: UUID,
        chatId: String,
        threshold: Int,
        messages: [Message],
        systemPrompt: String,
        parseResult: SlashParseResult,
        originalText: String,
        claudeService: ClaudeService,
        dataService: SwiftDataService,
        progress: ProgressCallbacks
    ) async throws -> SendResult {

        // --- Model Selection ---
        let effectiveModel: ClaudeModel
        let messageText: String

        switch parseResult {
        case .builtIn(let command, let remainder) where command.isPassthrough:
            effectiveModel = command.forcedModel ?? .fast
            messageText = remainder.isEmpty ? originalText : remainder
            print("🤖 Slash command: /\(command.rawValue) → \(effectiveModel.displayName)")
        default:
            let tips = RouterService.collectTips(from: messages)
            let classification = await RouterService.classify(
                userMessage: originalText,
                tips: tips,
                claudeService: claudeService
            )
            effectiveModel = classification.model
            messageText = originalText
        }

        // --- Build filtered conversation history ---
        let filteredMessages = await ContextFilteringService.getFilteredMessages(
            forChat: chatId,
            threshold: threshold,
            excludingLast: true,
            dataService: dataService
        )
        var apiMessages: [[String: Any]] = filteredMessages.map { msg in
            ContextFilteringService.buildAPIMessage(from: msg)
        }

        // --- Build current user message with image handling ---
        var currentMessageContent: [[String: Any]] = []

        for pending in imagesToSend {
            currentMessageContent.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": pending.mediaType,
                    "data": pending.base64Data
                ]
            ])
        }

        if !messageText.isEmpty {
            currentMessageContent.append([
                "type": "text",
                "text": messageText
            ])
        }

        if currentMessageContent.isEmpty {
            apiMessages.append(["role": "user", "content": messageText])
        } else if currentMessageContent.count == 1 && imagesToSend.isEmpty {
            apiMessages.append(["role": "user", "content": messageText])
        } else {
            apiMessages.append(["role": "user", "content": currentMessageContent])
        }

        // --- Streaming + Tool Loop ---
        let tools = ToolService.toolDefinitions
        var fullResponse = ""
        var totalStreamInputTokens = 0
        var totalStreamOutputTokens = 0
        var iteration = 0
        let maxIterations = 5
        var collectedMarkers: [String] = []

        while iteration < maxIterations {
            iteration += 1

            let result = try await claudeService.streamMessageWithTools(
                messages: apiMessages,
                model: effectiveModel,
                systemPrompt: systemPrompt,
                tools: tools,
                onTextChunk: { chunk in
                    fullResponse += chunk
                    Task { @MainActor in
                        progress.onTextChunk(chunk)
                    }
                }
            )

            totalStreamInputTokens += result.inputTokens
            totalStreamOutputTokens += result.outputTokens

            if result.stopReason == "end_turn" || result.toolCalls.isEmpty {
                break
            }

            // Build assistant content for the conversation
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

            // Execute tools
            var toolResults: [[String: Any]] = []
            for toolCall in result.toolCalls {
                let displayName = toolDisplayName(for: toolCall)
                await progress.onToolActivity(displayName)

                let toolResult: ToolResult
                if toolCall.name == "web_lookup" {
                    toolResult = await ToolService.executeWebLookup(
                        input: toolCall.input,
                        dataService: dataService
                    )
                } else {
                    toolResult = await ToolService.executeTool(
                        name: toolCall.name,
                        input: toolCall.input
                    )
                }

                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": toolCall.id,
                    "content": toolResult.textForLLM
                ])

                if let marker = toolResult.embeddedMarker {
                    collectedMarkers.append(marker)
                }
            }

            apiMessages.append(["role": "user", "content": toolResults])

            await progress.onToolActivity(nil)

            if !fullResponse.isEmpty {
                fullResponse += "\n\n"
                await progress.onTextChunk("\n\n")
            }
        }

        // --- Assemble result ---
        let (cleanedResponse, extractedTip) = RouterService.extractTip(from: fullResponse)

        if let tip = extractedTip {
            print("🏔️ Tip: \(tip)")
        }

        let markerPrefix = collectedMarkers.isEmpty ? "" : collectedMarkers.joined(separator: "\n") + "\n"
        let assistantMessage = Message(
            id: assistantMessageId,
            role: .assistant,
            content: markerPrefix + cleanedResponse,
            timestamp: Date(),
            turnId: turnId,
            isFinalResponse: true,
            inputTokens: totalStreamInputTokens,
            outputTokens: totalStreamOutputTokens,
            icebergTip: extractedTip ?? "",
            modelUsed: effectiveModel.rawValue
        )

        return SendResult(
            assistantMessage: assistantMessage,
            totalInputTokens: totalStreamInputTokens,
            totalOutputTokens: totalStreamOutputTokens,
            effectiveModel: effectiveModel
        )
    }

    // MARK: - Helpers

    /// Human-readable tool activity description for the UI indicator.
    private static func toolDisplayName(for toolCall: ToolCall) -> String {
        switch toolCall.name {
        case "search_web":
            let query = toolCall.input["query"] as? String ?? ""
            return "🔍 Searching: \(query)"
        case "get_weather":
            let location = toolCall.input["location"] as? String ?? "Catonsville"
            return "🌤️ Getting weather for \(location)"
        case "get_datetime":
            return "🕐 Checking date/time"
        case "web_lookup":
            let category = toolCall.input["category"] as? String ?? "search"
            let query = toolCall.input["query"] as? String ?? ""
            return "🌐 Looking up \(category): \(query)"
        default:
            return "🔧 Using \(toolCall.name)"
        }
    }
}

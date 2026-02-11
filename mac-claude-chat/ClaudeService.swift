//
//  ClaudeService.swift
//  mac-claude-chat
//
//  Created by Drew on 2/6/26.
//

import Foundation

// MARK: - API Request/Response Types

struct ClaudeAPIRequest: Codable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [ClaudeMessage]
    let stream: Bool
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeAPIResponse: Codable {
    let content: [ContentBlock]
    let usage: Usage
    
    struct ContentBlock: Codable {
        let text: String
    }
    
    struct Usage: Codable {
        let input_tokens: Int
        let output_tokens: Int
    }
}

// MARK: - Streaming Event Types

struct StreamEvent: Codable {
    let type: String
}

struct ContentBlockDelta: Codable {
    let type: String
    let delta: Delta
    
    struct Delta: Codable {
        let type: String
        let text: String
    }
}

struct MessageDelta: Codable {
    let type: String
    let delta: DeltaInfo
    let usage: Usage
    
    struct DeltaInfo: Codable {
        let stop_reason: String?
        let stop_sequence: String?
    }
    
    struct Usage: Codable {
        let output_tokens: Int
    }
}

struct MessageStart: Codable {
    let type: String
    let message: MessageInfo
    
    struct MessageInfo: Codable {
        let usage: Usage
    }
    
    struct Usage: Codable {
        let input_tokens: Int
        let output_tokens: Int
    }
}

// MARK: - Claude API Service

class ClaudeService {
    private let apiVersion = "2023-06-01"
    private let endpoint = "https://api.anthropic.com/v1/messages"
    
    /// Gets the API key from Keychain, falling back to environment variable
    private var apiKey: String? {
        if let keychainKey = KeychainService.getAPIKey(), !keychainKey.isEmpty {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return nil
    }
    
    /// Checks if an API key is available
    var hasAPIKey: Bool {
        apiKey != nil
    }
    
    func streamMessage(
        messages: [Message],
        model: ClaudeModel,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Int, Int) -> Void
    ) async throws {
        guard let apiKey = apiKey else {
            throw NSError(domain: "ClaudeAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key configured. Please add your Anthropic API key in Settings."])
        }
        
        let claudeMessages = messages.map { message in
            ClaudeMessage(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            )
        }
        
        let requestBody = ClaudeAPIRequest(
            model: model.rawValue,
            max_tokens: 8192,
            system: "You are Claude, a conversational AI assistant chatting with Drew, a retired engineer and programmer in Catonsville, Maryland.",
            messages: claudeMessages,
            stream: true
        )
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ClaudeAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }
        
        var inputTokens = 0
        var outputTokens = 0
        
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                
                if jsonString == "[DONE]" {
                    continue
                }
                
                guard let data = jsonString.data(using: .utf8) else {
                    continue
                }
                
                if let streamEvent = try? JSONDecoder().decode(StreamEvent.self, from: data) {
                    switch streamEvent.type {
                    case "message_start":
                        if let messageStart = try? JSONDecoder().decode(MessageStart.self, from: data) {
                            inputTokens = messageStart.message.usage.input_tokens
                        }
                        
                    case "content_block_delta":
                        if let delta = try? JSONDecoder().decode(ContentBlockDelta.self, from: data) {
                            await MainActor.run {
                                onChunk(delta.delta.text)
                            }
                        }
                        
                    case "message_delta":
                        if let messageDelta = try? JSONDecoder().decode(MessageDelta.self, from: data) {
                            outputTokens = messageDelta.usage.output_tokens
                        }
                        
                    default:
                        break
                    }
                }
            }
        }
        
        await MainActor.run {
            onComplete(inputTokens, outputTokens)
        }
    }

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
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw NSError(domain: "ClaudeAPI", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorBody)"])
        }

        var inputTokens = 0
        var outputTokens = 0
        var textContent = ""
        var toolCalls: [ToolCall] = []
        var stopReason = "end_turn"

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
                    let parsedInput: [String: Any]
                    if let jsonData = currentToolInputJson.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        parsedInput = parsed
                    } else {
                        parsedInput = [:]
                    }
                    toolCalls.append(ToolCall(id: toolId, name: toolName, input: parsedInput))
                }
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

    /// Non-streaming single-shot call for router classification and subagent work.
    /// Returns the raw text content from Claude's response.
    func singleShot(
        messages: [[String: Any]],
        model: ClaudeModel,
        systemPrompt: String,
        maxTokens: Int = 256
    ) async throws -> (text: String, inputTokens: Int, outputTokens: Int) {
        guard let apiKey = apiKey else {
            throw NSError(domain: "ClaudeAPI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No API key configured."])
        }

        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "ClaudeAPI", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw NSError(domain: "ClaudeAPI", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }

        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int ?? 0
        let outputTokens = usage?["output_tokens"] as? Int ?? 0

        return (text: text, inputTokens: inputTokens, outputTokens: outputTokens)
    }
}

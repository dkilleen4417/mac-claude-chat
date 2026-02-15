//
//  RouterService.swift
//  mac-claude-chat
//
//  Router: classifies user messages to select the optimal model tier.
//  Uses a one-shot Haiku call with iceberg tips for conversation context.
//

import Foundation

enum RouterService {

    // MARK: - Classification Prompt
    // Lives here as a single constant for easy tuning.

    static let classificationPrompt = """
        Classify the user's message into a processing tier based on the message \
        and conversation arc provided.

        HAIKU — Greetings, questions, casual chat, acknowledgments, follow-ups, \
        emotional support, small talk, advice, planning, opinions, preferences, \
        everyday conversation, simple explanations, simple code questions, \
        short creative writing, factual lookups, recommendations, scheduling, \
        reminders, anything that can be answered well without deep multi-step \
        reasoning and without using external tools.

        SONNET — Weather queries, web search queries, any request requiring \
        tool use, complex multi-step reasoning, writing or debugging substantial \
        code, detailed document analysis, extended creative writing requiring \
        craft, comparative analysis across multiple dimensions, technical \
        architecture, research synthesis from multiple sources, anything \
        requiring careful structured thought across multiple paragraphs.

        When in doubt between HAIKU and SONNET, choose HAIKU.
        Most messages should be HAIKU — SONNET is for tasks that genuinely \
        require deeper reasoning OR that require using tools (weather, search, etc).

        Do NOT classify as OPUS. The OPUS tier is not available for \
        automatic routing.

        Respond with ONLY a JSON object, no other text:
        {"tier": "HAIKU|SONNET", "confidence": 0.0-1.0}
        """

    // MARK: - Escalation Threshold

    static let confidenceThreshold = 0.8

    // MARK: - Classification

    /// Classify a user message using Haiku and return the recommended model.
    /// Assembles iceberg tips from prior turns as lightweight context.
    ///
    /// - Parameters:
    ///   - userMessage: The current user message text
    ///   - tips: Iceberg tips from all prior assistant messages, in chronological order
    ///   - claudeService: The service to make the API call
    /// - Returns: A tuple of (selectedModel, routerResponse, routerTokens)
    static func classify(
        userMessage: String,
        tips: [String],
        claudeService: ClaudeService
    ) async -> (model: ClaudeModel, response: RouterResponse, inputTokens: Int, outputTokens: Int) {
        // Build the user prompt with tips as context
        var prompt = ""
        if !tips.isEmpty {
            prompt += "[Conversation arc]\n"
            for (index, tip) in tips.enumerated() {
                prompt += "Turn \(index + 1): \(tip)\n"
            }
            prompt += "\n"
        }
        prompt += "[Current message]\n\(userMessage)"

        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]

        do {
            let result = try await claudeService.singleShot(
                messages: messages,
                model: .turbo,  // Always Haiku for classification
                systemPrompt: classificationPrompt,
                maxTokens: 64
            )

            let parsed = parseResponse(result.text)
            let finalModel = applyEscalation(parsed)

            print("🤖 Router: \(parsed.tier.displayName) (confidence: \(String(format: "%.2f", parsed.confidence))) → \(finalModel.displayName)")

            return (
                model: finalModel,
                response: parsed,
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens
            )
        } catch {
            // On router failure, default to Sonnet (safe middle ground)
            print("🤖 Router failed: \(error.localizedDescription) — defaulting to Sonnet")
            return (
                model: .fast,
                response: RouterResponse(tier: .fast, confidence: 0.0),
                inputTokens: 0,
                outputTokens: 0
            )
        }
    }

    // MARK: - Tip Extraction

    /// Collect iceberg tips from the conversation's assistant messages.
    /// Returns tips in chronological order.
    static func collectTips(from messages: [Message]) -> [String] {
        messages
            .filter { $0.role == .assistant && $0.isFinalResponse && !$0.icebergTip.isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
            .map { $0.icebergTip }
    }

    // MARK: - Tip Parsing

    /// Parse and strip the <!--tip:...--> marker from a response string.
    /// Returns the cleaned response and the extracted tip (if any).
    static func extractTip(from response: String) -> (cleanedResponse: String, tip: String?) {
        let result = MessageContentParser.extractAndStripTip(from: response)
        return (cleanedResponse: result.cleanedContent, tip: result.tip)
    }

    // MARK: - Private Helpers

    /// Parse the router's JSON response into a RouterResponse
    private static func parseResponse(_ text: String) -> RouterResponse {
        // Try to extract JSON from the response (handles markdown fences, extra text)
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If response contains newlines, try to extract just the JSON object
        if cleaned.contains("\n") {
            // Look for the JSON object (starts with { and ends with })
            if let startIndex = cleaned.firstIndex(of: "{"),
               let endIndex = cleaned.lastIndex(of: "}") {
                let jsonRange = startIndex...endIndex
                cleaned = String(cleaned[jsonRange])
            }
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tierString = json["tier"] as? String,
              let confidence = json["confidence"] as? Double else {
            // Parse failure: default to Haiku with full confidence (no escalation)
            print("🤖 Router: failed to parse '\(text)' — defaulting to Haiku")
            return RouterResponse(tier: .turbo, confidence: 1.0)
        }

        let tier: ClaudeModel
        switch tierString.uppercased() {
        case "HAIKU": tier = .turbo
        case "SONNET": tier = .fast
        case "OPUS": tier = .fast  // Opus not available via router; cap at Sonnet
        default: tier = .fast
        }

        return RouterResponse(tier: tier, confidence: confidence)
    }

    /// Apply confidence-based escalation within the two-tier system.
    /// Low-confidence Haiku → Sonnet. Everything else stays put.
    /// Opus is never reached through automatic routing.
    private static func applyEscalation(_ response: RouterResponse) -> ClaudeModel {
        // If router accidentally returns Opus, cap at Sonnet
        if response.tier == .premium {
            return .fast
        }

        guard response.confidence < confidenceThreshold else {
            return response.tier
        }

        // Only escalation: Haiku → Sonnet on low confidence
        switch response.tier {
        case .turbo: return .fast
        case .fast: return .fast
        case .premium: return .fast  // Should not reach here, but safety cap
        }
    }
}

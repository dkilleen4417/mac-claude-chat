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

        HAIKU — Greetings, simple factual questions, casual chat, acknowledgments, \
        time/date queries, simple follow-ups, emotional support, small talk.

        SONNET — Research questions, weather with discussion, explanations of concepts, \
        multi-step reasoning, code help, document analysis, creative writing, \
        planning, advice.

        OPUS — Complex architectural reasoning, deep analysis of multiple sources, \
        philosophical or nuanced ethical discussion, novel problem-solving requiring \
        extended chains of thought, tasks where the user explicitly requests \
        the highest quality reasoning.

        Respond with ONLY a JSON object, no other text:
        {"tier": "HAIKU|SONNET|OPUS", "confidence": 0.0-1.0}
        """

    // MARK: - Escalation Threshold

    static let confidenceThreshold = 0.7

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
        let pattern = "<!--tip:(.+?)-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (response, nil)
        }

        let range = NSRange(response.startIndex..., in: response)
        guard let match = regex.firstMatch(in: response, options: [], range: range),
              let tipRange = Range(match.range(at: 1), in: response) else {
            return (response, nil)
        }

        let tip = String(response[tipRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = regex.stringByReplacingMatches(in: response, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleaned, tip)
    }

    // MARK: - Private Helpers

    /// Parse the router's JSON response into a RouterResponse
    private static func parseResponse(_ text: String) -> RouterResponse {
        // Try to extract JSON from the response (handles markdown fences, extra text)
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tierString = json["tier"] as? String,
              let confidence = json["confidence"] as? Double else {
            // Parse failure: default to Sonnet with zero confidence (will escalate to Opus)
            print("🤖 Router: failed to parse '\(text)' — defaulting to Sonnet")
            return RouterResponse(tier: .fast, confidence: 0.0)
        }

        let tier: ClaudeModel
        switch tierString.uppercased() {
        case "HAIKU": tier = .turbo
        case "SONNET": tier = .fast
        case "OPUS": tier = .premium
        default: tier = .fast
        }

        return RouterResponse(tier: tier, confidence: confidence)
    }

    /// Apply confidence-based escalation: bump one tier if confidence < threshold
    private static func applyEscalation(_ response: RouterResponse) -> ClaudeModel {
        guard response.confidence < confidenceThreshold else {
            return response.tier
        }

        switch response.tier {
        case .turbo: return .fast      // Haiku → Sonnet
        case .fast: return .premium    // Sonnet → Opus
        case .premium: return .premium // Opus stays Opus
        }
    }
}

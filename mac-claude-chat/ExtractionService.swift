//
//  ExtractionService.swift
//  mac-claude-chat
//
//  Abstracts LLM-based structured data extraction from unstructured text.
//  PROVIDER-SPECIFIC: This service is provider-coupled.
//  For xAI fork: Change parameter from claudeService to xaiService, model from .turbo to grok-beta.
//

import Foundation

/// Service for extracting structured JSON from unstructured text using a small/fast LLM.
/// Provider-coupled: uses ClaudeService internally.
/// For xAI fork: rewrite to call xAI's API with grok-beta model.
enum ExtractionService {
    
    // MARK: - Extraction
    
    /// Extract structured JSON from unstructured text using a small/fast model.
    /// 
    /// Uses Haiku (Claude's fastest/cheapest model) for data extraction tasks.
    /// For xAI fork: replace with grok-beta API call.
    ///
    /// - Parameters:
    ///   - prompt: The extraction prompt (includes instructions + source text)
    ///   - maxTokens: Maximum tokens for the response (default 1024)
    ///   - claudeService: The Claude API service (will become xaiService in fork)
    /// - Returns: Tuple of (jsonText, inputTokens, outputTokens)
    /// - Throws: Network or API errors
    static func extractJSON(
        prompt: String,
        maxTokens: Int = 1024,
        claudeService: ClaudeService
    ) async throws -> (text: String, inputTokens: Int, outputTokens: Int) {
        return try await claudeService.singleShot(
            messages: [["role": "user", "content": prompt]],
            model: .turbo,  // Use Haiku (fast/cheap model) for extraction
            systemPrompt: "You extract structured data from text. Return only valid JSON.",
            maxTokens: maxTokens
        )
    }
}

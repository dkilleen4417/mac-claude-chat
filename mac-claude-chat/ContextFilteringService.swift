//
//  ContextFilteringService.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition.
//  Handles grade-based message filtering and API payload formatting.
//  No UI dependencies — pure data transformation.
//

import Foundation

enum ContextFilteringService {

    // MARK: - Filtered Messages for API

    /// Gets messages filtered by inclusion state for API calls.
    /// Turns are user+assistant pairs; if user message's textGrade == 0,
    /// the whole turn is excluded. Intermediate tool messages (isFinalResponse == false)
    /// are always excluded.
    ///
    /// - Parameters:
    ///   - chatId: The chat session to filter messages for.
    ///   - excludingLast: If true, excludes the last message (the one just sent).
    ///   - dataService: SwiftDataService for fetching messages with grades.
    /// - Returns: Array of Messages that are included in context.
    static func getFilteredMessages(
        forChat chatId: String,
        excludingLast: Bool,
        dataService: SwiftDataService
    ) async -> [Message] {
        do {
            let messagesWithGrades = try dataService.getMessagesWithGrades(forChat: chatId)
            var filtered: [Message] = []
            var i = 0
            let count = excludingLast ? messagesWithGrades.count - 1 : messagesWithGrades.count

            while i < count {
                let item = messagesWithGrades[i]

                // Skip intermediate tool loop messages (only include final responses)
                // This prunes tool_use/tool_result exchanges from previous turns
                guard item.isFinalResponse else {
                    i += 1
                    continue
                }

                if item.message.role == .user {
                    // Check if this user message is included (textGrade > 0)
                    if item.textGrade > 0 {
                        // Include user message
                        filtered.append(item.message)
                        // Include following assistant message if it's a final response and present
                        if i + 1 < count && messagesWithGrades[i + 1].message.role == .assistant {
                            // Only include if it's the final response for this turn
                            if messagesWithGrades[i + 1].isFinalResponse {
                                filtered.append(messagesWithGrades[i + 1].message)
                            }
                            i += 2
                            continue
                        }
                    } else {
                        // Skip this turn entirely (user + assistant if present)
                        if i + 1 < count && messagesWithGrades[i + 1].message.role == .assistant {
                            i += 2
                            continue
                        }
                    }
                }
                i += 1
            }

            return filtered
        } catch {
            print("Failed to get filtered messages: \(error)")
            return []
        }
    }

    // MARK: - API Message Formatting

    /// Build API message format from a stored Message.
    /// Converts image markers to placeholder text (images already analyzed by Claude).
    /// Strips all embedded markers from assistant messages.
    ///
    /// Note: This is only called for PAST messages in conversation history.
    /// Current-turn images are handled separately with full base64 data in sendMessage().
    ///
    /// - Parameter message: The stored Message to convert.
    /// - Returns: Dictionary in Claude API message format.
    static func buildAPIMessage(from message: Message) -> [String: Any] {
        let role = message.role == .user ? "user" : "assistant"

        // Check for image markers in user messages
        if message.role == .user {
            let (images, cleanText) = MessageContentParser.extractImagesAndCleanText(from: message.content)

            if !images.isEmpty {
                // Past images: replace with lightweight placeholder to save tokens
                // (base64 images can be 10,000-50,000+ tokens each)
                var contentBlocks: [[String: Any]] = []

                contentBlocks.append([
                    "type": "text",
                    "text": "[Image previously shared and analyzed]"
                ])

                // Add text block if there's text
                let trimmedText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    contentBlocks.append([
                        "type": "text",
                        "text": trimmedText
                    ])
                }

                return ["role": role, "content": contentBlocks]
            }
        }

        // For assistant messages or user messages without images, use simple string content
        // Strip any markers from assistant messages (weather, etc.) for the API
        let cleanContent = MessageContentParser.stripAllMarkers(message.content)
        return ["role": role, "content": cleanContent]
    }
}

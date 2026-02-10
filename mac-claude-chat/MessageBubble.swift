//
//  MessageBubble.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Message Bubble View

struct MessageBubble: View {
    let message: Message
    let turnGrade: Int  // The grade that applies to this turn (user's grade for both user and assistant)
    let threshold: Int
    let onGradeChange: (Int) -> Void
    let onCopyTurn: () -> Void

    @State private var expandedImageId: String?
    @State private var isHovered = false

    /// Computed opacity based on turn grade vs threshold
    /// Both user and assistant messages in a turn dim together
    private var dimOpacity: Double {
        if turnGrade >= threshold {
            return 1.0  // Full opacity - will be sent
        } else if turnGrade == 0 {
            return 0.2  // Heavily dimmed - grade 0
        } else {
            return 0.4  // Dimmed - excluded but not grade 0
        }
    }

    /// Parse image data from markers in content
    private var parsedImages: [(id: String, mediaType: String, base64Data: String)] {
        var images: [(id: String, mediaType: String, base64Data: String)] = []
        let pattern = "<!--image:(\\{.+?\\})-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return images
        }

        let range = NSRange(message.content.startIndex..., in: message.content)
        let matches = regex.matches(in: message.content, options: [], range: range)

        for match in matches {
            if let jsonRange = Range(match.range(at: 1), in: message.content) {
                let jsonString = String(message.content[jsonRange])
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
                   let id = json["id"],
                   let mediaType = json["media_type"],
                   let base64Data = json["data"] {
                    images.append((id: id, mediaType: mediaType, base64Data: base64Data))
                }
            }
        }
        return images
    }

    /// Content with image markers stripped
    private var cleanedContent: String {
        let pattern = "<!--image:\\{.+?\\}-->\\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return message.content
        }
        let range = NSRange(message.content.startIndex..., in: message.content)
        return regex.stringByReplacingMatches(in: message.content, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()

                // Grade control for user messages — appears on hover
                if isHovered {
                    GradeControl(grade: message.textGrade, onGradeChange: onGradeChange)
                        .transition(.opacity)
                }
            }

            if message.role == .assistant {
                Text("🧠")
                    .font(.body)
            }

            if message.role == .assistant {
                MarkdownMessageView(content: message.content)
            } else {
                // User message with potential images
                UserMessageContent(
                    images: parsedImages,
                    text: cleanedContent,
                    expandedImageId: $expandedImageId
                )
            }

            if message.role == .user {
                Text("😎")
                    .font(.body)
            }

            if message.role == .assistant {
                Spacer()
            }
        }
        .opacity(dimOpacity)
        .animation(.easeInOut(duration: 0.15), value: dimOpacity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Copy Message") {
                let cleanContent: String
                if message.role == .assistant {
                    // Strip markers from assistant messages
                    let weatherPattern = "<!--weather:.+?-->\\n?"
                    let imagePattern = "<!--image:\\{.+?\\}-->\\n?"
                    var text = message.content
                    if let regex = try? NSRegularExpression(pattern: weatherPattern, options: []) {
                        let range = NSRange(text.startIndex..., in: text)
                        text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
                    }
                    if let regex = try? NSRegularExpression(pattern: imagePattern, options: []) {
                        let range = NSRange(text.startIndex..., in: text)
                        text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
                    }
                    cleanContent = text.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    // Strip image markers from user messages
                    let imagePattern = "<!--image:\\{.+?\\}-->\\n?"
                    var text = message.content
                    if let regex = try? NSRegularExpression(pattern: imagePattern, options: []) {
                        let range = NSRange(text.startIndex..., in: text)
                        text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
                    }
                    cleanContent = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cleanContent, forType: .string)
                #else
                UIPasteboard.general.string = cleanContent
                #endif
            }

            Button("Copy Turn") {
                onCopyTurn()
            }
        }
    }
}

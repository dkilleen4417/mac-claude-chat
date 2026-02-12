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
        MessageContentParser.extractImages(from: message.content).map {
            (id: $0.id, mediaType: $0.mediaType, base64Data: $0.base64Data)
        }
    }

    /// Content with image markers stripped
    private var cleanedContent: String {
        MessageContentParser.stripImageMarkers(message.content)
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
                VStack(alignment: .leading, spacing: 4) {
                    // Iceberg tip as response header
                    if message.role == .assistant && !message.icebergTip.isEmpty {
                        Text("🏔️ \(message.icebergTip)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding(.bottom, 4)
                    }

                    MarkdownMessageView(content: message.content)

                    // Metadata footer: model, tokens, cost
                    if message.role == .assistant && message.isFinalResponse {
                        HStack(spacing: 4) {
                            if let model = ClaudeModel(rawValue: message.modelUsed) {
                                Text("\(model.emoji) \(model.displayName)")
                            } else if !message.modelUsed.isEmpty {
                                Text(message.modelUsed)
                            }

                            if message.inputTokens > 0 || message.outputTokens > 0 {
                                if !message.modelUsed.isEmpty {
                                    Text("•")
                                }
                                let totalTokens = message.inputTokens + message.outputTokens
                                Text("\(totalTokens) tokens")

                                if let model = ClaudeModel(rawValue: message.modelUsed) {
                                    Text("•")
                                    let inputCost = Double(message.inputTokens) / 1_000_000.0 * model.inputCostPerMillion
                                    let outputCost = Double(message.outputTokens) / 1_000_000.0 * model.outputCostPerMillion
                                    Text(String(format: "$%.4f", inputCost + outputCost))
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                }
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
                let cleanContent = MessageContentParser.stripAllMarkers(message.content)
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

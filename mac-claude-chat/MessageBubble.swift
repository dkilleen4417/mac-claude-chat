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
    let isIncluded: Bool  // Whether this turn is included in context
    let onToggleIncluded: (Bool) -> Void
    let onCopyTurn: () -> Void
    let onEditMessage: ((String) -> Void)?

    @State private var expandedImageId: String?
    @State private var isHovered = false
    @State private var isEditing: Bool = false
    @State private var editText: String = ""

    /// Computed opacity based on inclusion state
    /// Both user and assistant messages in a turn dim together
    private var dimOpacity: Double {
        isIncluded ? 1.0 : 0.3
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
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 0) {
            if message.role == .assistant {
                // Assistant message: sparkle icon + plain text
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkle")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        MarkdownMessageView(content: message.content)
                        
                        // Metadata footer — only on hover
                        if isHovered && message.isFinalResponse {
                            HStack(spacing: 4) {
                                if let model = ClaudeModel(rawValue: message.modelUsed) {
                                    Text(model.displayName)
                                }
                                if message.inputTokens > 0 || message.outputTokens > 0 {
                                    Text("•")
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
                            .foregroundStyle(.tertiary)
                            .transition(.opacity)
                        }
                    }
                    
                    Spacer(minLength: 60)
                }
            } else {
                // User message: bubble on right, context toggle on left
                HStack(alignment: .top, spacing: 8) {
                    Spacer(minLength: 60)
                    
                    // Context toggle
                    ContextToggle(isIncluded: isIncluded, onToggle: onToggleIncluded)
                        .frame(height: 22, alignment: .center)
                    
                    if isEditing {
                        VStack(alignment: .trailing, spacing: 6) {
                            TextEditor(text: $editText)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .frame(minHeight: 60, maxHeight: 200)
                                .background(Color.gray.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 18))

                            HStack(spacing: 8) {
                                if message.isEdited {
                                    Text("edited")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }
                                Spacer()
                                Button("Cancel") {
                                    isEditing = false
                                    editText = ""
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Button("Save") {
                                    let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        onEditMessage?(trimmed)
                                    }
                                    isEditing = false
                                    editText = ""
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    } else {
                        // User message in bubble with squared top-right corner
                        UserMessageContent(
                            images: parsedImages,
                            text: cleanedContent,
                            expandedImageId: $expandedImageId
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray).opacity(0.15))
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 20,
                                bottomLeadingRadius: 20,
                                bottomTrailingRadius: 20,
                                topTrailingRadius: 4
                            )
                        )
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .opacity(dimOpacity)
        .animation(.easeInOut(duration: 0.15), value: dimOpacity)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
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

            if message.role == .user && onEditMessage != nil {
                Divider()
                Button("Edit Message") {
                    editText = cleanedContent
                    isEditing = true
                }
            }
        }
        .onTapGesture(count: 2) {
            if message.role == .user && onEditMessage != nil {
                editText = cleanedContent
                isEditing = true
            }
        }
    }
}

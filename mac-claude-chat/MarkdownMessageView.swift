//
//  MarkdownMessageView.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition
//

import SwiftUI

// MARK: - Markdown Message View

struct MarkdownMessageView: View {
    let content: String

    /// Parsed weather data from embedded markers
    private var weatherData: [WeatherData] {
        MessageContentParser.extractWeather(from: content)
    }

    /// Content with weather markers stripped out
    private var cleanedContent: String {
        MessageContentParser.stripWeatherMarkers(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Render weather cards first
            ForEach(Array(weatherData.enumerated()), id: \.offset) { _, data in
                WeatherCardView(data: data)
            }

            // Then render the text content
            ForEach(parseContent(), id: \.id) { block in
                switch block.type {
                case .codeBlock(let language):
                    CodeBlockView(code: block.content, language: language)
                case .text:
                    // Render as single Text view for cross-paragraph selection
                    Text(buildAttributedText(from: block.content))
                        .textSelection(.enabled)
                }
            }
        }
        .lineSpacing(4)
    }

    /// Build a single AttributedString from markdown content, preserving paragraph breaks
    /// This allows text selection to span across paragraphs
    private func buildAttributedText(from content: String) -> AttributedString {
        var result = AttributedString()
        let paragraphs = content.components(separatedBy: "\n")

        for (index, paragraph) in paragraphs.enumerated() {
            if paragraph.isEmpty {
                // Empty line = paragraph break
                result.append(AttributedString("\n"))
            } else if let attributed = try? AttributedString(markdown: paragraph) {
                result.append(styleInlineCode(attributed))
            } else {
                result.append(AttributedString(paragraph))
            }

            // Add newline between paragraphs (but not after the last one)
            if index < paragraphs.count - 1 && !paragraph.isEmpty {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }

    private func parseContent() -> [MessageContentBlock] {
        var blocks: [MessageContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeLanguage = ""
        var blockId = 0

        // Use cleaned content (markers stripped)
        let lines = cleanedContent.components(separatedBy: "\n")

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    if !codeBlockContent.isEmpty {
                        blocks.append(MessageContentBlock(
                            id: blockId,
                            type: .codeBlock(language: codeLanguage),
                            content: codeBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        blockId += 1
                    }
                    codeBlockContent = ""
                    codeLanguage = ""
                    inCodeBlock = false
                } else {
                    if !currentText.isEmpty {
                        blocks.append(MessageContentBlock(
                            id: blockId,
                            type: .text,
                            content: currentText.trimmingCharacters(in: .newlines)
                        ))
                        blockId += 1
                        currentText = ""
                    }
                    let languageStart = line.index(line.startIndex, offsetBy: 3)
                    codeLanguage = String(line[languageStart...]).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
            } else {
                if inCodeBlock {
                    codeBlockContent += line + "\n"
                } else {
                    currentText += line + "\n"
                }
            }
        }

        if !currentText.isEmpty {
            let trimmed = currentText.trimmingCharacters(in: .newlines)
            if !trimmed.isEmpty {
                blocks.append(MessageContentBlock(
                    id: blockId,
                    type: .text,
                    content: trimmed
                ))
            }
        }

        if !codeBlockContent.isEmpty {
            blocks.append(MessageContentBlock(
                id: blockId,
                type: .codeBlock(language: codeLanguage),
                content: codeBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return blocks
    }

    /// Enhances inline code spans with visible background styling
    private func styleInlineCode(_ input: AttributedString) -> AttributedString {
        var result = input

        // Find runs with inline code presentation intent and style them
        for run in result.runs {
            if let inlineIntent = run.inlinePresentationIntent, inlineIntent.contains(.code) {
                let range = run.range
                result[range].font = .system(.body, design: .monospaced)
                result[range].backgroundColor = Color.gray.opacity(0.2)
            }
        }

        return result
    }
}

struct MessageContentBlock {
    let id: Int
    let type: BlockType
    let content: String

    enum BlockType {
        case text
        case codeBlock(language: String)
    }
}

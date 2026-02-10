//
//  ChatExporter.swift
//  mac-claude-chat
//
//  Selective markdown export using context management grades.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Chat Exporter

enum ChatExporter {

    /// Export a chat to markdown, filtered by grade threshold.
    /// Only includes turns where the user message's textGrade >= threshold
    /// and isFinalResponse == true (skips intermediate tool messages).
    static func exportMarkdown(chatName: String, messages: [Message], threshold: Int) -> String {
        // Filter to final responses only
        let finalMessages = messages.filter { $0.isFinalResponse }

        // Pair into turns and filter by threshold
        var includedTurns: [(user: Message, assistant: Message?)] = []
        var totalTurns = 0
        var i = 0

        while i < finalMessages.count {
            let msg = finalMessages[i]

            if msg.role == .user {
                totalTurns += 1
                let assistant: Message? = (i + 1 < finalMessages.count && finalMessages[i + 1].role == .assistant)
                    ? finalMessages[i + 1] : nil

                if msg.textGrade >= threshold {
                    includedTurns.append((user: msg, assistant: assistant))
                }

                i += (assistant != nil) ? 2 : 1
            } else {
                // Orphan assistant message (shouldn't happen, but handle gracefully)
                i += 1
            }
        }

        // Build markdown
        var lines: [String] = []

        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let exportDate = dateFormatter.string(from: Date())

        lines.append("# \(chatName)")
        lines.append("")
        lines.append("Exported: \(exportDate) | Turns: \(includedTurns.count) of \(totalTurns) (threshold ≥ \(threshold))")
        lines.append("")

        // Messages
        for turn in includedTurns {
            lines.append("---")
            lines.append("")
            lines.append("**User:**")
            lines.append(stripMarkers(from: turn.user.content))
            lines.append("")

            if let assistant = turn.assistant {
                lines.append("**Claude:**")
                lines.append(stripMarkers(from: assistant.content))
                lines.append("")
            }
        }

        if !includedTurns.isEmpty {
            lines.append("---")
        }

        return lines.joined(separator: "\n")
    }

    /// Strip all embedded markers (weather, image) from content
    private static func stripMarkers(from content: String) -> String {
        var result = content

        if let regex = try? NSRegularExpression(pattern: "<!--weather:.+?-->\\n?", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        if let regex = try? NSRegularExpression(pattern: "<!--image:\\{.+?\\}-->\\n?", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Markdown File Document

/// Simple FileDocument wrapper for .fileExporter (works on macOS and iOS)
struct MarkdownFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(data: data, encoding: .utf8) ?? ""
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8) ?? Data())
    }
}

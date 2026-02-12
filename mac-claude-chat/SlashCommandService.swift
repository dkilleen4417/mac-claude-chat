//
//  SlashCommandService.swift
//  mac-claude-chat
//
//  Slash Commands: parses user messages for /command prefixes.
//  Two layers: built-in commands (hardcoded) and user commands (SwiftData).
//  Phase 1: built-in only. Phase 2 adds user commands.
//

import Foundation

// MARK: - Built-In Commands

enum BuiltInCommand: String, CaseIterable {
    // Model overrides (passthrough — message still goes to API)
    case opus
    case sonnet
    case haiku

    // Local commands (execute immediately, no API call)
    case cost
    case help
    case clear
    case export

    var commandDescription: String {
        switch self {
        case .opus:    return "Force Opus model for this message"
        case .sonnet:  return "Force Sonnet model for this message"
        case .haiku:   return "Force Haiku model for this message"
        case .cost:    return "Show token cost summary for this chat"
        case .help:    return "List available slash commands"
        case .clear:   return "Clear the current chat"
        case .export:  return "Export chat to markdown"
        }
    }

    var isPassthrough: Bool {
        switch self {
        case .opus, .sonnet, .haiku: return true
        case .cost, .help, .clear, .export: return false
        }
    }

    var forcedModel: ClaudeModel? {
        switch self {
        case .opus:   return .premium
        case .sonnet: return .fast
        case .haiku:  return .turbo
        default:      return nil
        }
    }
}

// MARK: - Parse Result

enum SlashParseResult {
    case builtIn(command: BuiltInCommand, remainder: String)
    case none
}

// MARK: - Service

enum SlashCommandService {

    /// Parse a user message for a slash command prefix.
    /// Returns .none if the message doesn't start with a known command.
    static func parse(_ message: String) -> SlashParseResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return .none }

        // Extract the command word (everything between / and first space or end)
        let afterSlash = String(trimmed.dropFirst())
        let parts = afterSlash.split(separator: " ", maxSplits: 1)
        guard let commandWord = parts.first else { return .none }

        let commandStr = String(commandWord).lowercased()
        let remainder = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        // Check built-in commands
        if let builtIn = BuiltInCommand(rawValue: commandStr) {
            return .builtIn(command: builtIn, remainder: remainder)
        }

        return .none
    }

    /// Format help text listing all available commands.
    static func helpText() -> String {
        var lines: [String] = []
        lines.append("**Available Slash Commands**")
        lines.append("")
        lines.append("*Built-in:*")
        for cmd in BuiltInCommand.allCases {
            lines.append("  /\(cmd.rawValue) — \(cmd.commandDescription)")
        }
        return lines.joined(separator: "\n")
    }
}

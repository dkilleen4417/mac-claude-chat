//
//  ToolServiceStubs.swift
//  RouterEval
//
//  Minimal type definitions needed by ClaudeService for compilation.
//  RouterEval doesn't use streaming or tools, so these are stub types only.
//

import Foundation

/// Tool call parsed from Claude's streaming response
struct ToolCall {
    let id: String
    let name: String
    let input: [String: Any]
}

/// Result of a streaming API call, including any tool calls
struct StreamResult {
    let textContent: String
    let toolCalls: [ToolCall]
    let stopReason: String
    let inputTokens: Int
    let outputTokens: Int
}

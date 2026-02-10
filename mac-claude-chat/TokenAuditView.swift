//
//  TokenAuditView.swift
//  mac-claude-chat
//
//  Created by Drew on 2/10/26.
//

import SwiftUI

/// Diagnostic view showing per-turn token usage and costs
struct TokenAuditView: View {
    let messages: [Message]
    let model: ClaudeModel
    @Environment(\.dismiss) private var dismiss
    
    /// Turn data for display: groups user message with its token counts from the assistant response
    private var turns: [TurnTokenData] {
        var result: [TurnTokenData] = []
        var turnNumber = 0
        
        // Group by turnId - find user messages and their corresponding assistant responses
        var processedTurnIds = Set<String>()
        
        for message in messages where message.role == .user {
            let turnId = message.turnId
            guard !turnId.isEmpty, !processedTurnIds.contains(turnId) else { continue }
            processedTurnIds.insert(turnId)
            turnNumber += 1
            
            // Find the final assistant response for this turn (has the token counts)
            let assistantMessage = messages.first { 
                $0.turnId == turnId && 
                $0.role == .assistant && 
                $0.isFinalResponse 
            }
            
            let inputTokens = assistantMessage?.inputTokens ?? 0
            let outputTokens = assistantMessage?.outputTokens ?? 0
            
            // First ~40 chars of user message as label
            let userText = message.content
                .replacingOccurrences(of: "<!--[^>]+-->", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label = userText.count > 40 ? String(userText.prefix(40)) + "..." : userText
            
            result.append(TurnTokenData(
                number: turnNumber,
                label: label,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                model: model
            ))
        }
        
        return result
    }
    
    /// Running cumulative input tokens for staircase visualization
    private var cumulativeInputTokens: [Int] {
        var cumulative = 0
        return turns.map { turn in
            cumulative += turn.inputTokens
            return cumulative
        }
    }
    
    /// Summary statistics
    private var totalInputTokens: Int { turns.reduce(0) { $0 + $1.inputTokens } }
    private var totalOutputTokens: Int { turns.reduce(0) { $0 + $1.outputTokens } }
    private var totalCost: Double {
        let inputCost = Double(totalInputTokens) / 1_000_000 * model.inputCostPerMillion
        let outputCost = Double(totalOutputTokens) / 1_000_000 * model.outputCostPerMillion
        return inputCost + outputCost
    }
    private var averageInputPerTurn: Int {
        turns.isEmpty ? 0 : totalInputTokens / turns.count
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary header
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(totalInputTokens + totalOutputTokens)")
                                .font(.title2.monospacedDigit())
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .center, spacing: 4) {
                            Text("Estimated Cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("$\(totalCost, specifier: "%.4f")")
                                .font(.title2.monospacedDigit())
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Avg Input/Turn")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(averageInputPerTurn)")
                                .font(.title2.monospacedDigit())
                        }
                    }
                    
                    HStack {
                        Text("Input: \(totalInputTokens)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("Output: \(totalOutputTokens)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("\(turns.count) turns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(model.displayName)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                
                Divider()
                
                // Per-turn list
                if turns.isEmpty {
                    VStack(spacing: 8) {
                        Text("No turn data available")
                            .foregroundStyle(.secondary)
                        Text("Token counts are recorded for new conversations.\nOld turns will show 0 tokens.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(turns.enumerated()), id: \.element.number) { index, turn in
                            HStack {
                                // Turn number
                                Text("#\(turn.number)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .leading)
                                
                                // User message label
                                Text(turn.label)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Token counts
                                VStack(alignment: .trailing, spacing: 2) {
                                    if turn.inputTokens > 0 || turn.outputTokens > 0 {
                                        Text("In: \(turn.inputTokens)")
                                            .font(.caption.monospacedDigit())
                                        Text("Out: \(turn.outputTokens)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("--")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(width: 80, alignment: .trailing)
                                
                                // Cost
                                Text("$\(turn.cost, specifier: "%.4f")")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(turn.cost > 0 ? .primary : .tertiary)
                                    .frame(width: 70, alignment: .trailing)
                                
                                // Running cumulative (staircase)
                                if index < cumulativeInputTokens.count {
                                    Text("Σ \(cumulativeInputTokens[index])")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.blue)
                                        .frame(width: 70, alignment: .trailing)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Token Audit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}

/// Data for a single turn in the token audit
private struct TurnTokenData {
    let number: Int
    let label: String
    let inputTokens: Int
    let outputTokens: Int
    let model: ClaudeModel
    
    var cost: Double {
        let inputCost = Double(inputTokens) / 1_000_000 * model.inputCostPerMillion
        let outputCost = Double(outputTokens) / 1_000_000 * model.outputCostPerMillion
        return inputCost + outputCost
    }
}

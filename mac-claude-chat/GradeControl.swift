//
//  GradeControl.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition
//

import SwiftUI

// MARK: - Grade Control View

struct GradeControl: View {
    let grade: Int
    let onGradeChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0...5, id: \.self) { value in
                Button {
                    onGradeChange(value)
                } label: {
                    Circle()
                        .fill(value <= grade ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
                .buttonStyle(.plain)
            }

            Text("\(grade)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 12)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
        .help("Grade: \(grade) — click dots to change")
    }
}

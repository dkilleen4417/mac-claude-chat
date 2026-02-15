//
//  GradeControl.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition
//

import SwiftUI

// MARK: - Context Toggle View

struct ContextToggle: View {
    let isIncluded: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isIncluded)
        } label: {
            Circle()
                .fill(isIncluded ? Color.primary : Color.gray.opacity(0.3))
                .frame(width: 10, height: 10)
        }
        .buttonStyle(.plain)
        .help(isIncluded ? "Included in context — click to exclude" : "Excluded from context — click to include")
    }
}

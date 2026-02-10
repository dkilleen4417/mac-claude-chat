//
//  PlatformUtilities.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 3 decomposition
//

import SwiftUI

// MARK: - Platform Colors

enum PlatformColor {
    static var windowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    static var textBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}

// MARK: - Input Height Preference Key (for iOS auto-sizing)

struct InputHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 36
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

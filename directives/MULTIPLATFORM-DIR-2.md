# MULTIPLATFORM-DIR-2: App Entry Point + Commands

## Overview
Adapt mac_claude_chatApp.swift so the macOS menu bar commands compile
on iOS without losing any Mac functionality.

## The Problem
The `.commands` modifier and `CommandGroup`/`CommandMenu` types are
macOS-only. iOS has no menu bar. We need to wrap the entire commands
block so it only compiles on macOS.

## Edit: mac_claude_chatApp.swift

Replace the **entire file** with:

```swift
//
//  mac_claude_chatApp.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//

import SwiftUI
import SwiftData

@main
struct mac_claude_chatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [ChatSession.self, ChatMessage.self])
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .newChat, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button("Clear Chat") {
                    NotificationCenter.default.post(name: .clearChat, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Button("Delete Chat") {
                    NotificationCenter.default.post(name: .deleteChat, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            
            CommandMenu("View") {
                Menu("Model") {
                    Button("💨 Haiku 4.5") {
                        NotificationCenter.default.post(name: .selectModel, object: ClaudeModel.turbo)
                    }
                    .keyboardShortcut("1", modifiers: .command)
                    
                    Button("⚡ Sonnet 4.5") {
                        NotificationCenter.default.post(name: .selectModel, object: ClaudeModel.fast)
                    }
                    .keyboardShortcut("2", modifiers: .command)
                    
                    Button("🚀 Opus 4.6") {
                        NotificationCenter.default.post(name: .selectModel, object: ClaudeModel.premium)
                    }
                    .keyboardShortcut("3", modifiers: .command)
                }
            }
            
            CommandGroup(after: .appSettings) {
                Button("API Key Settings...") {
                    NotificationCenter.default.post(name: .showAPIKeySettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }
}
```

## What Changed
- Added `#if os(macOS)` around the entire `.commands { ... }` block
- Everything else is identical
- On iOS, the app launches with just the WindowGroup and model container
- The keyboard shortcuts (Cmd+N, Cmd+K, etc.) still work on iPad with
  a hardware keyboard because SwiftUI routes them through the responder
  chain — but the menu bar UI is macOS-only

## Note on iOS Navigation
The existing sidebar "New Chat" button, model picker menu, and "Clear Chat"
button in ContentView.swift already provide all these functions through
the UI. iOS users lose nothing — they just don't have the menu bar shortcuts.

## Verification
- File should compile cleanly for both macOS and iOS targets
- Only one `#if os(macOS)` block wrapping `.commands`

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
                
                Divider()
                
                Button("Publish Chat\u{2026}") {
                    NotificationCenter.default.post(name: .publishChat, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
            
            CommandMenu("View") {
                Menu("Model") {
                    Button("💨 Haiku 4.5") {
                        NotificationCenter.default.post(name: .selectModel, object: ClaudeModel.turbo)
                    }
                    .keyboardShortcut("1", modifiers: .command)
                    
                    Button("⚡ Sonnet 4") {
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

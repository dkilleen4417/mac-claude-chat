//
//  Models.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//
//  CloudKit-compatible SwiftData models.
//  Requirements: no @Attribute(.unique), all properties have defaults,
//  all relationships are optional.
//

import Foundation
import SwiftData

// MARK: - SwiftData Persistent Models (CloudKit-Compatible)

@Model
final class ChatSession {
    // CloudKit: removed @Attribute(.unique) — uniqueness enforced in app logic
    var chatId: String = ""
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var lastUpdated: Date = Date()
    var isDefault: Bool = false
    
    // CloudKit: relationship must be optional
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
    var messages: [ChatMessage]? = []
    
    init(
        chatId: String,
        totalInputTokens: Int = 0,
        totalOutputTokens: Int = 0,
        lastUpdated: Date = Date(),
        isDefault: Bool = false,
        messages: [ChatMessage] = []
    ) {
        self.chatId = chatId
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.lastUpdated = lastUpdated
        self.isDefault = isDefault
        self.messages = messages
    }
    
    /// Safe accessor for messages (unwraps optional for CloudKit compatibility)
    var safeMessages: [ChatMessage] {
        get { messages ?? [] }
        set { messages = newValue }
    }
}

@Model
final class ChatMessage {
    var messageId: String = ""
    var role: String = ""
    var content: String = ""
    var timestamp: Date = Date()
    
    // CloudKit: already optional — good
    var session: ChatSession?
    
    init(
        messageId: String = UUID().uuidString,
        role: String,
        content: String,
        timestamp: Date = Date()
    ) {
        self.messageId = messageId
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - In-Memory Models

struct Message: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    
    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
    
    enum Role {
        case user
        case assistant
    }
}

struct ChatMetadata {
    let chatId: String
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let lastUpdated: Date
    let isDefault: Bool
}

struct ChatInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let lastUpdated: Date
    let isDefault: Bool
    
    static func == (lhs: ChatInfo, rhs: ChatInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Claude Model Configuration

enum ClaudeModel: String, CaseIterable, Identifiable {
    case turbo = "claude-haiku-4-5-20251001"
    case fast = "claude-sonnet-4-5-20250929"
    case premium = "claude-opus-4-6"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .turbo: return "Haiku 4.5"
        case .fast: return "Sonnet 4.5"
        case .premium: return "Opus 4.6"
        }
    }
    
    var emoji: String {
        switch self {
        case .turbo: return "💨"
        case .fast: return "⚡"
        case .premium: return "🚀"
        }
    }
    
    var inputCostPerMillion: Double {
        switch self {
        case .turbo: return 0.80
        case .fast: return 3.00
        case .premium: return 5.00
        }
    }
    
    var outputCostPerMillion: Double {
        switch self {
        case .turbo: return 4.00
        case .fast: return 15.00
        case .premium: return 25.00
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newChat = Notification.Name("newChat")
    static let clearChat = Notification.Name("clearChat")
    static let deleteChat = Notification.Name("deleteChat")
    static let selectModel = Notification.Name("selectModel")
    static let showAPIKeySettings = Notification.Name("showAPIKeySettings")
}

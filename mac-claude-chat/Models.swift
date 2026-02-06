//
//  Models.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//

import Foundation
import SwiftData

@Model
final class ChatSession {
    @Attribute(.unique) var chatId: String
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var lastUpdated: Date
    var isDefault: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
    var messages: [ChatMessage]
    
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
}

@Model
final class ChatMessage {
    var messageId: String
    var role: String
    var content: String
    var timestamp: Date
    
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

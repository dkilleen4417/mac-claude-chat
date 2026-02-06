//
//  SwiftDataService.swift
//  mac-claude-chat
//
//  Created by Drew on 2/6/26.
//

import Foundation
import SwiftData

class SwiftDataService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func saveMessage(_ message: Message, chatId: String) throws {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        
        guard let session = try modelContext.fetch(descriptor).first else {
            return
        }
        
        let chatMessage = ChatMessage(
            messageId: message.id.uuidString,
            role: message.role == .user ? "user" : "assistant",
            content: message.content,
            timestamp: message.timestamp
        )
        chatMessage.session = session
        session.messages.append(chatMessage)
        session.lastUpdated = Date()
        
        try modelContext.save()
    }
    
    func loadMessages(forChat chatId: String) throws -> [Message] {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        
        guard let session = try modelContext.fetch(descriptor).first else {
            return []
        }
        
        return session.messages
            .sorted { $0.timestamp < $1.timestamp }
            .map { chatMessage in
                Message(
                    id: UUID(uuidString: chatMessage.messageId) ?? UUID(),
                    role: chatMessage.role == "user" ? .user : .assistant,
                    content: chatMessage.content,
                    timestamp: chatMessage.timestamp
                )
            }
    }
    
    func saveMetadata(chatId: String, inputTokens: Int, outputTokens: Int, isDefault: Bool = false) throws {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        
        if let session = try modelContext.fetch(descriptor).first {
            session.totalInputTokens = inputTokens
            session.totalOutputTokens = outputTokens
            session.lastUpdated = Date()
            session.isDefault = isDefault
        } else {
            let session = ChatSession(
                chatId: chatId,
                totalInputTokens: inputTokens,
                totalOutputTokens: outputTokens,
                lastUpdated: Date(),
                isDefault: isDefault
            )
            modelContext.insert(session)
        }
        
        try modelContext.save()
    }
    
    func loadAllChats() throws -> [ChatInfo] {
        let descriptor = FetchDescriptor<ChatSession>()
        let sessions = try modelContext.fetch(descriptor)
        
        return sessions.map { session in
            ChatInfo(
                id: session.chatId,
                name: session.chatId,
                lastUpdated: session.lastUpdated,
                isDefault: session.isDefault || session.chatId == "Scratch Pad"
            )
        }
    }
    
    func createChat(name: String) throws {
        let session = ChatSession(
            chatId: name,
            totalInputTokens: 0,
            totalOutputTokens: 0,
            lastUpdated: Date(),
            isDefault: false
        )
        modelContext.insert(session)
        try modelContext.save()
    }
    
    func loadMetadata(forChat chatId: String) throws -> ChatMetadata? {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        
        guard let session = try modelContext.fetch(descriptor).first else {
            return nil
        }
        
        return ChatMetadata(
            chatId: session.chatId,
            totalInputTokens: session.totalInputTokens,
            totalOutputTokens: session.totalOutputTokens,
            lastUpdated: session.lastUpdated,
            isDefault: session.isDefault
        )
    }
    
    func deleteChat(_ chatId: String) throws {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        
        if let session = try modelContext.fetch(descriptor).first {
            modelContext.delete(session)
            try modelContext.save()
        }
    }
}

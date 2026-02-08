//
//  SwiftDataService.swift
//  mac-claude-chat
//
//  Created by Drew on 2/6/26.
//
//  Updated for CloudKit compatibility — uses safeMessages accessor
//  for the optional relationship on ChatSession.
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
        session.safeMessages.append(chatMessage)
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
        
        return session.safeMessages
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
        // CloudKit: no unique constraint, so check for duplicates in app logic
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == name }
        )
        
        if try modelContext.fetch(descriptor).first != nil {
            // Chat already exists — skip creation
            return
        }
        
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

    func renameChat(from oldChatId: String, to newChatId: String) throws {
        // Check if target name already exists
        let existingDescriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == newChatId }
        )
        if try modelContext.fetch(existingDescriptor).first != nil {
            throw NSError(domain: "SwiftDataService", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "A chat with that name already exists"])
        }

        // Find and update the session
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == oldChatId }
        )

        guard let session = try modelContext.fetch(descriptor).first else {
            throw NSError(domain: "SwiftDataService", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Chat not found"])
        }

        session.chatId = newChatId
        session.lastUpdated = Date()
        try modelContext.save()
    }
    
    // MARK: - CloudKit Deduplication
    
    /// Merges duplicate ChatSessions that can arise when multiple devices
    /// create the same chatId before CloudKit syncs (no unique constraint).
    /// Keeps the oldest session, moves messages from duplicates into it.
    func deduplicateSessions() throws {
        let descriptor = FetchDescriptor<ChatSession>()
        let allSessions = try modelContext.fetch(descriptor)
        
        // Group by chatId
        var grouped: [String: [ChatSession]] = [:]
        for session in allSessions {
            grouped[session.chatId, default: []].append(session)
        }
        
        for (_, sessions) in grouped where sessions.count > 1 {
            // Sort by lastUpdated — keep the oldest (first created)
            let sorted = sessions.sorted { $0.lastUpdated < $1.lastUpdated }
            let keeper = sorted[0]
            
            for duplicate in sorted.dropFirst() {
                // Move messages from duplicate to keeper
                for message in duplicate.safeMessages {
                    message.session = keeper
                    keeper.safeMessages.append(message)
                }
                // Accumulate tokens
                keeper.totalInputTokens += duplicate.totalInputTokens
                keeper.totalOutputTokens += duplicate.totalOutputTokens
                // Preserve isDefault flag
                if duplicate.isDefault { keeper.isDefault = true }
                // Remove the duplicate (without cascade since we moved messages)
                duplicate.messages = []
                modelContext.delete(duplicate)
            }
        }
        
        try modelContext.save()
    }
}

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
    
    func saveMessage(_ message: Message, chatId: String, textGrade: Int = 5, imageGrade: Int = 5, turnId: String = "", isFinalResponse: Bool = true) throws {
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
            timestamp: message.timestamp,
            textGrade: textGrade,
            imageGrade: imageGrade,
            turnId: turnId,
            isFinalResponse: isFinalResponse
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
                    timestamp: chatMessage.timestamp,
                    textGrade: chatMessage.textGrade,
                    imageGrade: chatMessage.imageGrade,
                    turnId: chatMessage.turnId,
                    isFinalResponse: chatMessage.isFinalResponse
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
    
// MARK: - Context Management
    
    /// Gets the context threshold for a chat session
    func getContextThreshold(forChat chatId: String) -> Int {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        
        guard let session = try? modelContext.fetch(descriptor).first else {
            return 0
        }
        return session.contextThreshold
    }
    
    /// Sets the context threshold for a chat session
    func setContextThreshold(forChat chatId: String, threshold: Int) throws {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        
        guard let session = try modelContext.fetch(descriptor).first else {
            return
        }
        
        session.contextThreshold = max(0, min(5, threshold))  // Clamp to 0-5
        try modelContext.save()
    }
    
    /// Gets messages with their grades for a chat session, for filtering
    func getMessagesWithGrades(forChat chatId: String) throws -> [(message: Message, textGrade: Int, imageGrade: Int, turnId: String, isFinalResponse: Bool)] {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        
        guard let session = try modelContext.fetch(descriptor).first else {
            return []
        }
        
        return session.safeMessages
            .sorted { $0.timestamp < $1.timestamp }
            .map { chatMessage in
                (
                    message: Message(
                        id: UUID(uuidString: chatMessage.messageId) ?? UUID(),
                        role: chatMessage.role == "user" ? .user : .assistant,
                        content: chatMessage.content,
                        timestamp: chatMessage.timestamp,
                        textGrade: chatMessage.textGrade,
                        imageGrade: chatMessage.imageGrade,
                        turnId: chatMessage.turnId,
                        isFinalResponse: chatMessage.isFinalResponse
                    ),
                    textGrade: chatMessage.textGrade,
                    imageGrade: chatMessage.imageGrade,
                    turnId: chatMessage.turnId,
                    isFinalResponse: chatMessage.isFinalResponse
                )
            }
    }
    
    /// Updates the text grade for a message by its ID
    func setTextGrade(forMessageId messageId: String, grade: Int) throws {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.messageId == messageId }
        )
        
        guard let message = try modelContext.fetch(descriptor).first else {
            return
        }
        
        message.textGrade = max(0, min(5, grade))  // Clamp to 0-5
        try modelContext.save()
    }
    
    /// Updates grades for all messages in a chat (bulk action)
    func setAllGrades(forChat chatId: String, textGrade: Int, imageGrade: Int) throws {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        
        guard let session = try modelContext.fetch(descriptor).first else {
            return
        }
        
        let clampedTextGrade = max(0, min(5, textGrade))
        let clampedImageGrade = max(0, min(5, imageGrade))
        
        for message in session.safeMessages where message.role == "user" {
            message.textGrade = clampedTextGrade
            message.imageGrade = clampedImageGrade
        }
        
        try modelContext.save()
    }
    
    // MARK: - Turn ID Migration
    
    /// Backfills turnId for existing messages that lack one.
    /// Groups messages into turns: each user message starts a turn, and all
    /// following assistant messages until the next user message share that turnId.
    /// Only the last assistant message in each turn is marked as isFinalResponse = true.
    func backfillTurnIds() throws {
        let descriptor = FetchDescriptor<ChatSession>()
        let allSessions = try modelContext.fetch(descriptor)
        
        var migratedCount = 0
        
        for session in allSessions {
            let messages = session.safeMessages.sorted { $0.timestamp < $1.timestamp }
            
            // Skip if no messages need migration
            let needsMigration = messages.contains { $0.turnId.isEmpty }
            guard needsMigration else { continue }
            
            var currentTurnId = ""
            var turnAssistantMessages: [ChatMessage] = []
            
            for message in messages {
                // Skip if already has a turnId
                guard message.turnId.isEmpty else {
                    // If this message has a turnId, update tracking state
                    if message.role == "user" {
                        // Finalize previous turn's assistant messages
                        markFinalResponse(in: turnAssistantMessages)
                        turnAssistantMessages = []
                        currentTurnId = message.turnId
                    } else {
                        turnAssistantMessages.append(message)
                    }
                    continue
                }
                
                if message.role == "user" {
                    // Finalize previous turn's assistant messages
                    markFinalResponse(in: turnAssistantMessages)
                    turnAssistantMessages = []
                    
                    // Start a new turn
                    currentTurnId = UUID().uuidString
                    message.turnId = currentTurnId
                    message.isFinalResponse = true  // User messages are always "final"
                    migratedCount += 1
                } else {
                    // Assistant message: use current turn's ID
                    if currentTurnId.isEmpty {
                        // Orphan assistant message without a preceding user message
                        currentTurnId = UUID().uuidString
                    }
                    message.turnId = currentTurnId
                    message.isFinalResponse = false  // Will be updated by markFinalResponse
                    turnAssistantMessages.append(message)
                    migratedCount += 1
                }
            }
            
            // Finalize the last turn's assistant messages
            markFinalResponse(in: turnAssistantMessages)
        }
        
        if migratedCount > 0 {
            try modelContext.save()
            print("Backfilled turnId for \(migratedCount) messages")
        }
    }
    
    /// Marks the last assistant message in a turn as the final response
    private func markFinalResponse(in assistantMessages: [ChatMessage]) {
        guard !assistantMessages.isEmpty else { return }
        // All messages default to isFinalResponse = false during migration
        // Only the last one gets marked true
        assistantMessages.last?.isFinalResponse = true
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

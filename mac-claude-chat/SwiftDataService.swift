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
    
    var modelContainer: ModelContainer {
        modelContext.container
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func saveMessage(_ message: Message, chatId: String, textGrade: Int = 5, imageGrade: Int = 5, turnId: String = "", isFinalResponse: Bool = true, inputTokens: Int = 0, outputTokens: Int = 0) throws {
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
            isFinalResponse: isFinalResponse,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            icebergTip: message.icebergTip,
            modelUsed: message.modelUsed
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
                    isFinalResponse: chatMessage.isFinalResponse,
                    inputTokens: chatMessage.inputTokens,
                    outputTokens: chatMessage.outputTokens,
                    icebergTip: chatMessage.icebergTip,
                    modelUsed: chatMessage.modelUsed,
                    isEdited: chatMessage.isEdited
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
                        isFinalResponse: chatMessage.isFinalResponse,
                        inputTokens: chatMessage.inputTokens,
                        outputTokens: chatMessage.outputTokens,
                        icebergTip: chatMessage.icebergTip,
                        modelUsed: chatMessage.modelUsed,
                        isEdited: chatMessage.isEdited
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
    
    /// Updates the text content of a user message (for inline editing).
    /// Only user messages are editable. Sets isEdited flag and updates session timestamp.
    func updateMessageContent(messageId: String, newContent: String) throws {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.messageId == messageId }
        )
        
        guard let message = try modelContext.fetch(descriptor).first else {
            return
        }
        
        // Only user messages are editable
        guard message.role == "user" else {
            return
        }
        
        message.content = newContent
        message.isEdited = true
        
        // Update parent session timestamp
        if let session = message.session {
            session.lastUpdated = Date()
        }
        
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
    
    func clearMessages(forChat chatId: String) throws {
        let backgroundContext = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        guard let session = try backgroundContext.fetch(descriptor).first else { return }

        let messagesToDelete = Array(session.safeMessages)
        for message in messagesToDelete {
            backgroundContext.delete(message)
        }

        session.totalInputTokens = 0
        session.totalOutputTokens = 0
        session.lastUpdated = Date()
        try backgroundContext.save()
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

    // MARK: - Web Tools CRUD

    /// Returns all web tool categories, sorted by displayOrder.
    func loadWebToolCategories() throws -> [WebToolCategory] {
        let descriptor = FetchDescriptor<WebToolCategory>(
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Returns enabled web tool categories only, sorted by displayOrder.
    func loadEnabledWebToolCategories() throws -> [WebToolCategory] {
        let descriptor = FetchDescriptor<WebToolCategory>(
            predicate: #Predicate { $0.isEnabled == true },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Finds a web tool category by keyword (for tool dispatch).
    func findWebToolCategory(byKeyword keyword: String) throws -> WebToolCategory? {
        let descriptor = FetchDescriptor<WebToolCategory>(
            predicate: #Predicate { $0.keyword == keyword && $0.isEnabled == true }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Creates a new web tool category. Returns the created category.
    @discardableResult
    func createWebToolCategory(
        name: String,
        keyword: String,
        extractionHint: String = "",
        iconName: String = "globe",
        displayOrder: Int = 0
    ) throws -> WebToolCategory {
        // CloudKit: no unique constraint — check for duplicate keyword
        let existing = FetchDescriptor<WebToolCategory>(
            predicate: #Predicate { $0.keyword == keyword }
        )
        if try modelContext.fetch(existing).first != nil {
            throw NSError(domain: "SwiftDataService", code: 10,
                         userInfo: [NSLocalizedDescriptionKey: "A web tool category with keyword '\(keyword)' already exists"])
        }

        let category = WebToolCategory(
            name: name,
            keyword: keyword,
            extractionHint: extractionHint,
            iconName: iconName,
            displayOrder: displayOrder
        )
        modelContext.insert(category)
        try modelContext.save()
        return category
    }

    /// Deletes a web tool category and its sources (cascade).
    func deleteWebToolCategory(_ categoryId: String) throws {
        let descriptor = FetchDescriptor<WebToolCategory>(
            predicate: #Predicate { $0.categoryId == categoryId }
        )
        if let category = try modelContext.fetch(descriptor).first {
            modelContext.delete(category)
            try modelContext.save()
        }
    }

    /// Adds a source to a web tool category.
    @discardableResult
    func addWebToolSource(
        toCategoryId categoryId: String,
        name: String,
        urlPattern: String,
        extractionHint: String = "",
        priority: Int = 1,
        notes: String = ""
    ) throws -> WebToolSource? {
        let descriptor = FetchDescriptor<WebToolCategory>(
            predicate: #Predicate { $0.categoryId == categoryId }
        )
        guard let category = try modelContext.fetch(descriptor).first else {
            return nil
        }

        let source = WebToolSource(
            name: name,
            urlPattern: urlPattern,
            extractionHint: extractionHint,
            priority: priority,
            notes: notes
        )
        source.category = category
        category.safeSources.append(source)
        try modelContext.save()
        return source
    }

    /// Deletes a web tool source by its sourceId.
    func deleteWebToolSource(_ sourceId: String) throws {
        let descriptor = FetchDescriptor<WebToolSource>(
            predicate: #Predicate { $0.sourceId == sourceId }
        )
        if let source = try modelContext.fetch(descriptor).first {
            modelContext.delete(source)
            try modelContext.save()
        }
    }

    /// Returns enabled sources for a category, sorted by priority (ascending).
    /// This is the fallback chain order: priority 1 first, then 2, then 3.
    func loadEnabledSources(forCategoryKeyword keyword: String) throws -> [WebToolSource] {
        guard let category = try findWebToolCategory(byKeyword: keyword) else {
            return []
        }
        return category.safeSources
            .filter { $0.isEnabled }
            .sorted { $0.priority < $1.priority }
    }

    // MARK: - Web Tools Default Seeding

    /// Seeds default web tool categories and sources on first launch.
    /// Safe to call multiple times — skips if any categories already exist.
    func seedDefaultWebTools() throws {
        let descriptor = FetchDescriptor<WebToolCategory>()
        let existingCount = try modelContext.fetchCount(descriptor)
        guard existingCount == 0 else { return }

        // --- Weather category ---
        let weather = WebToolCategory(
            name: "Weather",
            keyword: "weather",
            extractionHint: "Current conditions, temperature, humidity, wind, and 7-day forecast",
            iconName: "sun.max",
            displayOrder: 0
        )
        modelContext.insert(weather)

        let nws = WebToolSource(
            name: "NWS Forecast",
            urlPattern: "https://forecast.weather.gov/MapClick.php?lat={lat}&lon={lon}",
            extractionHint: "Current conditions, temperature, humidity, wind, and 7-day forecast from National Weather Service",
            priority: 1,
            notes: "National Weather Service — free, no API key, US coverage"
        )
        nws.category = weather
        weather.safeSources.append(nws)

        let wttr = WebToolSource(
            name: "wttr.in",
            urlPattern: "https://wttr.in/{city}?format=v2",
            extractionHint: "Current conditions and forecast in text format",
            priority: 2,
            notes: "Global coverage, text-friendly output"
        )
        wttr.category = weather
        weather.safeSources.append(wttr)

        try modelContext.save()
        print("Seeded default web tools: 1 category, 2 sources")
    }

    // MARK: - Web Tools CloudKit Deduplication

    /// Merges duplicate WebToolCategory records that can arise from CloudKit sync.
    /// Keeps the oldest record per keyword, moves sources from duplicates.
    func deduplicateWebToolCategories() throws {
        let descriptor = FetchDescriptor<WebToolCategory>()
        let allCategories = try modelContext.fetch(descriptor)

        var grouped: [String: [WebToolCategory]] = [:]
        for category in allCategories {
            grouped[category.keyword, default: []].append(category)
        }

        for (_, categories) in grouped where categories.count > 1 {
            let sorted = categories.sorted { $0.createdAt < $1.createdAt }
            let keeper = sorted[0]

            for duplicate in sorted.dropFirst() {
                for source in duplicate.safeSources {
                    source.category = keeper
                    keeper.safeSources.append(source)
                }
                duplicate.sources = []
                modelContext.delete(duplicate)
            }
        }

        try modelContext.save()
    }
}

//
//  ChatViewModel.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition.
//  Owns all chat state and intent methods. ContentView observes this
//  and composes the UI.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
class ChatViewModel {

    // MARK: - Published State

    var selectedChat: String? = "Scratch Pad"
    var messageText: String = ""
    var inputHeight: CGFloat = 36
    var messages: [Message] = []
    var isLoading: Bool = false
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var errorMessage: String?
    var chats: [ChatInfo] = []
    var showingNewChatDialog: Bool = false
    var newChatName: String = ""
    var streamingMessageId: UUID?
    var streamingContent: String = ""
    var selectedModel: ClaudeModel = .turbo  // TODO: Remove after TokenAuditView rework
    var showingAPIKeySetup: Bool = false
    var showingWebToolManager: Bool = false
    var needsAPIKey: Bool = false
    var toolActivityMessage: String?
    var renamingChatId: String?
    var renameChatText: String = ""
    var showUnderConstruction: Bool = false
    var pendingImages: [PendingImage] = []
    var showingImagePicker: Bool = false
    var contextThreshold: Int = 0
    var showingTokenAudit: Bool = false
    var isClearing: Bool = false

    // MARK: - Services

    let claudeService = ClaudeService()
    private var _dataService: SwiftDataService?

    /// Must be set via `configure(modelContext:)` before use.
    var dataService: SwiftDataService {
        guard let ds = _dataService else {
            fatalError("ChatViewModel.dataService accessed before configure(modelContext:) was called")
        }
        return ds
    }

    /// Called once from ContentView's .task or .onAppear to inject the ModelContext.
    func configure(modelContext: ModelContext) {
        guard _dataService == nil else { return }  // Only configure once
        _dataService = SwiftDataService(modelContext: modelContext)
    }

    // MARK: - System Prompt

    var systemPrompt: String {
        // Load custom template from UserDefaults, or use default if not set
        let storedTemplate = UserDefaults.standard.string(forKey: "systemPromptTemplate")
        let basePrompt = storedTemplate ?? defaultSystemPrompt
        
        // If the prompt contains the web tools placeholder, inject it
        if basePrompt.contains("\\(webToolsPromptSection)") {
            return basePrompt.replacingOccurrences(
                of: "\\(webToolsPromptSection)",
                with: webToolsPromptSection
            )
        } else {
            // No placeholder found, return as-is
            return basePrompt
        }
    }
    
    /// Default system prompt template (matches SettingsView's default)
    /// PROVIDER-SPECIFIC: "You are Claude" identity string (line 92).
    /// For xAI fork: Change to "You are Grok" or appropriate identity.
    private var defaultSystemPrompt: String {
        """
        You are Claude, an AI assistant in a natural conversation with Drew (Andrew Killeen), a retired engineer and programmer in Catonsville, Maryland.

        CONVERSATIONAL APPROACH:
        - This is a real conversation, not a series of isolated requests and responses.
        - Build on what's been discussed, reference earlier parts of conversation.
        - Express curiosity, surprise, agreement, or thoughtful disagreement naturally.
        - Be genuine and conversational, not formulaic.

        USER CONTEXT:
        - Name: Drew (Andrew Killeen), prefers "Drew"
        - Location: Catonsville, Maryland (Eastern timezone)
        - Background: 74-year-old retired engineer, 54 years of coding experience
        - Current interests: Python/Streamlit/SwiftUI development, AI applications, gardening, weather

        TOOL USAGE:
        You have tools available — use them confidently:
        - get_datetime: Get current date and time (Eastern timezone)
        - search_web: Search the web for current information (news, sports, events, research)
        - get_weather: Get current weather (defaults to Catonsville, Maryland)
        - web_lookup: Look up information from curated web sources
        Don't deflect with "I don't have real-time data" — search for it.
        IMPORTANT: Use all tools silently. Never announce that you are checking the date, time, weather, or searching. Just do it and weave the results into your response naturally.
        You can call multiple tools in a single response when needed.
        For weather queries with no specific location, default to Drew's location.

        TEMPORAL REFERENCES:
        When the user mentions any relative time ("last Sunday", "this week", "yesterday", "recently", "the latest"), ALWAYS call get_datetime first to anchor your reasoning to the actual current date before proceeding.
        Never assume you know today's date — always verify with the tool.
        Use tools silently — don't announce that you're checking the date, time, or weather. Just do it and incorporate the results naturally.

        ICEBERG TIP:
        At the very end of every response, append a one-line summary of this exchange wrapped in an HTML comment marker. This summary captures the essence of what was discussed or accomplished in this turn — it will be used for conversation context in future turns. Format:
        <!--tip:Brief summary of what was discussed or accomplished-->
        Keep tips under 20 words. Examples:
        <!--tip:Greeted user, casual check-in-->
        <!--tip:Explained SwiftData CloudKit constraints and migration strategy-->
        <!--tip:Provided weather for Catonsville, clear skies 44°F-->
        """
    }

    // MARK: - Helpers

    func friendlyTime(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<60: return "Just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86400: return "\(Int(seconds / 3600))h ago"
        case ..<172800: return "Yesterday"
        case ..<604800: return "\(Int(seconds / 86400))d ago"
        case ..<2592000: return "\(Int(seconds / 604800))w ago"
        default: return "Long ago"
        }
    }

    var webToolsPromptSection: String {
        do {
            let categories = try dataService.loadEnabledWebToolCategories()
            if categories.isEmpty {
                return "No web tool categories are currently configured."
            }
            var lines: [String] = ["Available categories:"]
            for category in categories {
                let sourceCount = category.safeSources.filter { $0.isEnabled }.count
                let hint = category.extractionHint.isEmpty ? "" : " — \(category.extractionHint)"
                lines.append("- \(category.keyword): \(category.name)\(hint) (\(sourceCount) source\(sourceCount == 1 ? "" : "s"))")
            }
            return lines.joined(separator: "\n        ")
        } catch {
            print("Failed to load web tool categories for prompt: \(error)")
            return "No web tool categories are currently configured."
        }
    }

    var sortedChats: [ChatInfo] {
        chats.sorted { lhs, rhs in
            if lhs.isDefault { return true }
            if rhs.isDefault { return false }
            return lhs.lastUpdated > rhs.lastUpdated
        }
    }

    func calculateCost() -> String {
        var totalCost = 0.0
        for message in messages where message.role == .assistant && !message.modelUsed.isEmpty {
            if let model = ClaudeModel(rawValue: message.modelUsed) {
                totalCost += Double(message.inputTokens) / 1_000_000.0 * model.inputCostPerMillion
                totalCost += Double(message.outputTokens) / 1_000_000.0 * model.outputCostPerMillion
            }
        }
        return String(format: "%.4f", totalCost)
    }

    // MARK: - Database Operations

    func initializeDatabase() {
        do {
            try dataService.deduplicateSessions()
        } catch {
            print("Deduplication check: \(error)")
        }

        do {
            try dataService.seedDefaultWebTools()
            try dataService.deduplicateWebToolCategories()
        } catch {
            print("Web tools initialization: \(error)")
        }

        do {
            try dataService.backfillTurnIds()
        } catch {
            print("TurnId backfill: \(error)")
        }

        ensureScratchPadExists()
        loadAllChats()

        if let chatId = selectedChat {
            loadChat(chatId: chatId)
        }
    }

    private func ensureScratchPadExists() {
        do {
            let allChats = try dataService.loadAllChats()
            if !allChats.contains(where: { $0.id == "Scratch Pad" }) {
                try dataService.saveMetadata(
                    chatId: "Scratch Pad",
                    inputTokens: 0,
                    outputTokens: 0,
                    isDefault: true
                )
            }
        } catch {
            print("Failed to ensure Scratch Pad exists: \(error)")
        }
    }

    func loadAllChats() {
        do {
            chats = try dataService.loadAllChats()
        } catch {
            errorMessage = "Failed to load chats: \(error.localizedDescription)"
            print("Load chats error: \(error)")
        }
    }

    func createNewChat() {
        let trimmedName = newChatName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        do {
            try dataService.createChat(name: trimmedName)
            loadAllChats()
            selectedChat = trimmedName
            newChatName = ""
        } catch {
            errorMessage = "Failed to create chat: \(error.localizedDescription)"
        }
    }

    func deleteChat(_ chat: ChatInfo) {
        guard !chat.isDefault else { return }
        guard !isClearing else { return }

        let chatId = chat.id
        isClearing = true

        // Step 1: Update UI immediately (optimistic)
        chats.removeAll { $0.id == chatId }
        if selectedChat == chatId {
            selectedChat = "Scratch Pad"
        }

        // Step 2: Delete on background context
        let container = dataService.modelContainer
        Task.detached { [weak self] in
            let backgroundContext = ModelContext(container)
            backgroundContext.autosaveEnabled = false

            do {
                let sessionDescriptor = FetchDescriptor<ChatSession>(
                    predicate: #Predicate { $0.chatId == chatId }
                )
                guard let session = try backgroundContext.fetch(sessionDescriptor).first else {
                    await MainActor.run { [weak self] in self?.isClearing = false }
                    return
                }

                // Delete messages explicitly first (avoid cascade on main context)
                let messagesToDelete = Array(session.safeMessages)
                session.messages = []
                try backgroundContext.save()

                for message in messagesToDelete {
                    backgroundContext.delete(message)
                }

                // Now delete the empty session
                backgroundContext.delete(session)
                try backgroundContext.save()

                print("✅ Background delete completed: \(chatId) (\(messagesToDelete.count) messages)")
            } catch {
                print("❌ Background delete failed: \(error)")
                // Reload chats from DB to restore accurate sidebar
                await MainActor.run { [weak self] in
                    self?.loadAllChats()
                }
            }

            await MainActor.run { [weak self] in self?.isClearing = false }
        }
    }

    func renameCurrentChat() {
        guard let oldId = renamingChatId else { return }
        let newName = renameChatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }

        do {
            try dataService.renameChat(from: oldId, to: newName)
            loadAllChats()

            if selectedChat == oldId {
                selectedChat = newName
            }

            renamingChatId = nil
            renameChatText = ""
        } catch {
            errorMessage = "Failed to rename chat: \(error.localizedDescription)"
        }
    }

    func loadChat(chatId: String) {
        guard !isClearing else { return }

        do {
            let loadedMessages = try dataService.loadMessages(forChat: chatId)
            messages = loadedMessages

            if let metadata = try dataService.loadMetadata(forChat: chatId) {
                totalInputTokens = metadata.totalInputTokens
                totalOutputTokens = metadata.totalOutputTokens
            } else {
                totalInputTokens = 0
                totalOutputTokens = 0
            }

            contextThreshold = dataService.getContextThreshold(forChat: chatId)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load chat: \(error.localizedDescription)"
            print("Load Error: \(error)")
        }
    }

    // MARK: - Context Management

    func updateContextThreshold(_ newValue: Int) {
        guard let chatId = selectedChat else { return }

        do {
            try dataService.setContextThreshold(forChat: chatId, threshold: newValue)
        } catch {
            errorMessage = "Failed to update threshold: \(error.localizedDescription)"
        }
    }

    func confirmBulkGrade(grade: Int) {
        guard let chatId = selectedChat else { return }

        do {
            try dataService.setAllGrades(forChat: chatId, textGrade: grade, imageGrade: grade)
            loadChat(chatId: chatId)
        } catch {
            errorMessage = "Failed to update grades: \(error.localizedDescription)"
        }
    }

    func updateMessageGrade(messageId: UUID, grade: Int) {
        do {
            try dataService.setTextGrade(forMessageId: messageId.uuidString, grade: grade)
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].textGrade = grade
                messages[index].imageGrade = grade
            }
        } catch {
            errorMessage = "Failed to update grade: \(error.localizedDescription)"
        }
    }

    // MARK: - Message Editing

    func editMessage(messageId: UUID, newText: String) {
        // Find the message in memory
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        
        let message = messages[index]
        
        // Only user messages are editable
        guard message.role == .user else { return }
        
        // Don't save empty edits
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Preserve existing image markers, replace only the text portion
        let (images, _) = MessageContentParser.extractImagesAndCleanText(from: message.content)
        var imageMarkers: [String] = []
        for image in images {
            let markerJson: [String: String] = [
                "id": image.id,
                "media_type": image.mediaType,
                "data": image.base64Data
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: markerJson),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                imageMarkers.append("<!--image:\(jsonString)-->")
            }
        }
        
        let markerPrefix = imageMarkers.isEmpty ? "" : imageMarkers.joined(separator: "\n") + "\n"
        let fullContent = markerPrefix + trimmed
        
        // Persist
        do {
            try dataService.updateMessageContent(
                messageId: messageId.uuidString,
                newContent: fullContent
            )
            
            // Update in-memory
            messages[index] = Message(
                id: message.id,
                role: message.role,
                content: fullContent,
                timestamp: message.timestamp,
                textGrade: message.textGrade,
                imageGrade: message.imageGrade,
                turnId: message.turnId,
                isFinalResponse: message.isFinalResponse,
                inputTokens: message.inputTokens,
                outputTokens: message.outputTokens,
                icebergTip: message.icebergTip,
                modelUsed: message.modelUsed,
                isEdited: true
            )
            
            loadAllChats()  // Refresh sidebar timestamps
        } catch {
            errorMessage = "Failed to edit message: \(error.localizedDescription)"
        }
    }

    // MARK: - Clipboard

    func copyTurn(for message: Message) {
        let turnMessages: [Message]
        if !message.turnId.isEmpty {
            turnMessages = messages.filter { $0.turnId == message.turnId && $0.isFinalResponse }
        } else {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                var pair: [Message] = []
                if message.role == .user {
                    pair.append(message)
                    if index + 1 < messages.count && messages[index + 1].role == .assistant {
                        pair.append(messages[index + 1])
                    }
                } else {
                    if index > 0 && messages[index - 1].role == .user {
                        pair.append(messages[index - 1])
                    }
                    pair.append(message)
                }
                turnMessages = pair
            } else {
                turnMessages = [message]
            }
        }

        var parts: [String] = []
        for msg in turnMessages.sorted(by: { $0.timestamp < $1.timestamp }) {
            let cleaned = MessageContentParser.stripAllMarkers(msg.content)
            let prefix = msg.role == .user ? "**Drew:**" : "**Claude:**"
            parts.append("\(prefix)\n\(cleaned)")
        }
        let fullText = parts.joined(separator: "\n\n")

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)
        #else
        UIPasteboard.general.string = fullText
        #endif
    }

    // MARK: - Publishing

    func publishChat(chatId: String) {
        do {
            let chatMessages = try dataService.loadMessages(forChat: chatId)
            let threshold = dataService.getContextThreshold(forChat: chatId)
            let content = ChatExporter.exportMarkdown(
                chatName: chatId,
                messages: chatMessages,
                threshold: threshold
            )
            let filename = "\(chatId).md"

            #if os(macOS)
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
                panel.nameFieldStringValue = filename
                panel.title = "Publish Chat"
                panel.prompt = "Save"

                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        do {
                            try content.write(to: url, atomically: true, encoding: .utf8)
                            print("Published chat to: \(url)")
                        } catch {
                            self.errorMessage = "Failed to save: \(error.localizedDescription)"
                        }
                    }
                }
            }
            #endif
        } catch {
            errorMessage = "Failed to export: \(error.localizedDescription)"
        }
    }

    func clearCurrentChat() {
        guard let chatId = selectedChat else { return }
        guard !isClearing else { return }  // Prevent re-entrance

        isClearing = true

        // Step 1: Set in-memory state to empty FIRST.
        // SwiftUI will render an empty chat on its next pass.
        messages = []
        totalInputTokens = 0
        totalOutputTokens = 0
        errorMessage = nil

        // Update the sidebar entry in-place (no DB read)
        if let index = chats.firstIndex(where: { $0.id == chatId }) {
            chats[index] = ChatInfo(
                id: chatId,
                name: chatId,
                lastUpdated: Date(),
                isDefault: chats[index].isDefault
            )
        }

        // Step 2: Delete SwiftData objects on a background context.
        // Explicit per-message deletion avoids cascade merge overhead.
        let container = dataService.modelContainer
        Task.detached { [weak self] in
            let backgroundContext = ModelContext(container)
            backgroundContext.autosaveEnabled = false

            do {
                let descriptor = FetchDescriptor<ChatSession>(
                    predicate: #Predicate { $0.chatId == chatId }
                )
                guard let session = try backgroundContext.fetch(descriptor).first else {
                    await MainActor.run { [weak self] in self?.isClearing = false }
                    return
                }

                // Sever relationship first — lightweight merge when saved
                let orphanedMessages = Array(session.safeMessages)
                session.messages = []
                session.totalInputTokens = 0
                session.totalOutputTokens = 0
                session.lastUpdated = Date()
                try backgroundContext.save()

                // Delete orphaned messages in a second pass
                for message in orphanedMessages {
                    backgroundContext.delete(message)
                }
                try backgroundContext.save()

                print("✅ Background clear completed: \(orphanedMessages.count) messages deleted")
            } catch {
                print("❌ Background clear failed: \(error)")
            }

            await MainActor.run { [weak self] in self?.isClearing = false }
        }
    }

    // MARK: - Image Attachment

    func addImageFromData(_ data: Data) {
        if let pending = ImageAttachmentManager.processForAttachment(data) {
            pendingImages.append(pending)
        }
    }

    func removePendingImage(id: UUID) {
        pendingImages.removeAll { $0.id == id }
    }

    func handleImageDrop(providers: [NSItemProvider]) {
        ImageAttachmentManager.processDropProviders(providers) { [weak self] imageData in
            self?.addImageFromData(imageData)
        }
    }

    func handleFileImport(result: Result<[URL], Error>) {
        ImageAttachmentManager.processFileImport(result) { imageData in
            addImageFromData(imageData)
        }
    }

    // MARK: - Message Sending

    func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !pendingImages.isEmpty else { return }
        guard let chatId = selectedChat else { return }

        // --- Slash Command Parsing ---
        let parseResult = SlashCommandService.parse(trimmedText)

        // Handle local commands immediately (no API call)
        switch parseResult {
        case .builtIn(let command, _) where !command.isPassthrough:
            messageText = ""
            switch command {
            case .help:
                let helpMessage = Message(
                    role: .assistant,
                    content: SlashCommandService.helpText(),
                    timestamp: Date()
                )
                messages.append(helpMessage)
            case .cost:
                showingTokenAudit = true
            case .clear:
                NotificationCenter.default.post(name: .clearChat, object: nil)
            case .export:
                NotificationCenter.default.post(name: .publishChat, object: nil)
            default:
                break
            }
            return
        default:
            break
        }

        // Build image markers for persistence
        var imageMarkers: [String] = []
        for pending in pendingImages {
            let markerJson: [String: String] = [
                "id": pending.id.uuidString,
                "media_type": pending.mediaType,
                "data": pending.base64Data
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: markerJson),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                imageMarkers.append("<!--image:\(jsonString)-->")
            }
        }

        let markerPrefix = imageMarkers.isEmpty ? "" : imageMarkers.joined(separator: "\n") + "\n"
        let persistedContent = markerPrefix + trimmedText

        let imagesToSend = pendingImages
        let sendThreshold = contextThreshold
        let turnId = UUID().uuidString
        let assistantMessageId = UUID()

        let userMessage = Message(
            role: .user,
            content: persistedContent,
            timestamp: Date(),
            turnId: turnId,
            isFinalResponse: true
        )

        messages.append(userMessage)

        do {
            try dataService.saveMessage(userMessage, chatId: chatId, turnId: turnId, isFinalResponse: true)
        } catch {
            print("Failed to save user message: \(error)")
        }

        messageText = ""
        pendingImages = []
        inputHeight = 36
        errorMessage = nil
        streamingMessageId = assistantMessageId
        streamingContent = ""
        toolActivityMessage = nil
        isLoading = true

        Task {
            do {
                let result = try await MessageSendingService.send(
                    messageForAPI: trimmedText,
                    imagesToSend: imagesToSend,
                    turnId: turnId,
                    assistantMessageId: assistantMessageId,
                    chatId: chatId,
                    threshold: sendThreshold,
                    messages: messages,
                    systemPrompt: systemPrompt,
                    parseResult: parseResult,
                    originalText: trimmedText,
                    claudeService: claudeService,
                    dataService: dataService,
                    progress: MessageSendingService.ProgressCallbacks(
                        onTextChunk: { [weak self] chunk in
                            self?.streamingContent += chunk
                        },
                        onToolActivity: { [weak self] activity in
                            self?.toolActivityMessage = activity
                        }
                    )
                )

                totalInputTokens += result.totalInputTokens
                totalOutputTokens += result.totalOutputTokens
                messages.append(result.assistantMessage)
                streamingMessageId = nil
                streamingContent = ""
                toolActivityMessage = nil
                isLoading = false

                try dataService.saveMessage(
                    result.assistantMessage,
                    chatId: chatId,
                    turnId: turnId,
                    isFinalResponse: true,
                    inputTokens: result.totalInputTokens,
                    outputTokens: result.totalOutputTokens
                )

                let isDefault = chatId == "Scratch Pad"
                try dataService.saveMetadata(
                    chatId: chatId,
                    inputTokens: totalInputTokens,
                    outputTokens: totalOutputTokens,
                    isDefault: isDefault
                )

                loadAllChats()

            } catch {
                isLoading = false
                streamingMessageId = nil
                streamingContent = ""
                toolActivityMessage = nil
                errorMessage = "Error: \(error.localizedDescription)"
                print("Claude API Error: \(error)")
            }
        }
    }
}

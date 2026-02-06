//
//  ContentView.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//

import SwiftUI
import SwiftData

// MARK: - Data Transfer Objects

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

// MARK: - SwiftData Service

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

// MARK: - Model Configuration

enum ClaudeModel: String, CaseIterable, Identifiable {
    case turbo = "claude-haiku-4-5-20251001"
    case fast = "claude-sonnet-4-20250514"
    case premium = "claude-opus-4-6"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .turbo: return "Haiku 4.5"
        case .fast: return "Sonnet 4"
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

// MARK: - Claude API Service

struct ClaudeAPIRequest: Codable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [ClaudeMessage]
    let stream: Bool
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeAPIResponse: Codable {
    let content: [ContentBlock]
    let usage: Usage
    
    struct ContentBlock: Codable {
        let text: String
    }
    
    struct Usage: Codable {
        let input_tokens: Int
        let output_tokens: Int
    }
}

struct StreamEvent: Codable {
    let type: String
}

struct ContentBlockDelta: Codable {
    let type: String
    let delta: Delta
    
    struct Delta: Codable {
        let type: String
        let text: String
    }
}

struct MessageDelta: Codable {
    let type: String
    let delta: DeltaInfo
    let usage: Usage
    
    struct DeltaInfo: Codable {
        let stop_reason: String?
        let stop_sequence: String?
    }
    
    struct Usage: Codable {
        let output_tokens: Int
    }
}

struct MessageStart: Codable {
    let type: String
    let message: MessageInfo
    
    struct MessageInfo: Codable {
        let usage: Usage
    }
    
    struct Usage: Codable {
        let input_tokens: Int
        let output_tokens: Int
    }
}

class ClaudeService {
    private let apiVersion = "2023-06-01"
    private let endpoint = "https://api.anthropic.com/v1/messages"
    
    /// Gets the API key from Keychain, falling back to environment variable
    private var apiKey: String? {
        // Try Keychain first, then environment variable
        if let keychainKey = KeychainService.getAPIKey(), !keychainKey.isEmpty {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return nil
    }
    
    /// Checks if an API key is available
    var hasAPIKey: Bool {
        apiKey != nil
    }
    
    func streamMessage(
        messages: [Message],
        model: ClaudeModel,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Int, Int) -> Void
    ) async throws {
        guard let apiKey = apiKey else {
            throw NSError(domain: "ClaudeAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key configured. Please add your Anthropic API key in Settings."])
        }
        
        let claudeMessages = messages.map { message in
            ClaudeMessage(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            )
        }
        
        let requestBody = ClaudeAPIRequest(
            model: model.rawValue,
            max_tokens: 8192,
            system: "You are Claude, a conversational AI assistant chatting with Drew, a retired engineer and programmer in Catonsville, Maryland.",
            messages: claudeMessages,
            stream: true
        )
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ClaudeAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }
        
        var inputTokens = 0
        var outputTokens = 0
        
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                
                if jsonString == "[DONE]" {
                    continue
                }
                
                guard let data = jsonString.data(using: .utf8) else {
                    continue
                }
                
                if let streamEvent = try? JSONDecoder().decode(StreamEvent.self, from: data) {
                    switch streamEvent.type {
                    case "message_start":
                        if let messageStart = try? JSONDecoder().decode(MessageStart.self, from: data) {
                            inputTokens = messageStart.message.usage.input_tokens
                        }
                        
                    case "content_block_delta":
                        if let delta = try? JSONDecoder().decode(ContentBlockDelta.self, from: data) {
                            await MainActor.run {
                                onChunk(delta.delta.text)
                            }
                        }
                        
                    case "message_delta":
                        if let messageDelta = try? JSONDecoder().decode(MessageDelta.self, from: data) {
                            outputTokens = messageDelta.usage.output_tokens
                        }
                        
                    default:
                        break
                    }
                }
            }
        }
        
        await MainActor.run {
            onComplete(inputTokens, outputTokens)
        }
    }
}

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

// MARK: - Notification Names
extension Notification.Name {
    static let newChat = Notification.Name("newChat")
    static let clearChat = Notification.Name("clearChat")
    static let deleteChat = Notification.Name("deleteChat")
    static let selectModel = Notification.Name("selectModel")
    static let showAPIKeySettings = Notification.Name("showAPIKeySettings")
}

struct ContentView: View {
    @State private var selectedChat: String? = "Scratch Pad"
    @State private var messageText: String = ""
    @State private var messages: [Message] = []
    @State private var isLoading: Bool = false
    @State private var totalInputTokens: Int = 0
    @State private var totalOutputTokens: Int = 0
    @State private var errorMessage: String?
    @State private var chats: [ChatInfo] = []
    @State private var showingNewChatDialog: Bool = false
    @State private var newChatName: String = ""
    @State private var streamingMessageId: UUID?
    @State private var streamingContent: String = ""
    @State private var selectedModel: ClaudeModel = .fast
    @State private var showingAPIKeySetup: Bool = false
    @State private var needsAPIKey: Bool = false
    
    @Environment(\.modelContext) private var modelContext
    private let claudeService = ClaudeService()
    
    private var dataService: SwiftDataService {
        SwiftDataService(modelContext: modelContext)
    }
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: {
                        showingNewChatDialog = true
                    }) {
                        Label("New Chat", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Divider()
                
                List(sortedChats, id: \.id, selection: $selectedChat) { chat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.name)
                        Text(friendlyTime(from: chat.lastUpdated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !chat.isDefault {
                            Button(role: .destructive) {
                                deleteChat(chat)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            chatView
        }
        .task {
            // Initialize database if we have an API key
            if claudeService.hasAPIKey {
                initializeDatabase()
            }
        }
        .onChange(of: needsAPIKey) { oldValue, newValue in
            // When API key is saved, initialize database
            if oldValue == true && newValue == false {
                initializeDatabase()
            }
        }
        .onChange(of: selectedChat) { oldValue, newValue in
            if let chatId = newValue {
                loadChat(chatId: chatId)
            }
        }
        .alert("New Chat", isPresented: $showingNewChatDialog) {
            TextField("Chat Name", text: $newChatName)
            Button("Cancel", role: .cancel) {
                newChatName = ""
            }
            Button("Create") {
                createNewChat()
            }
            .disabled(newChatName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the new chat")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            showingNewChatDialog = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearChat)) { _ in
            clearCurrentChat()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteChat)) { _ in
            if let chatId = selectedChat,
               let chat = chats.first(where: { $0.id == chatId }),
               !chat.isDefault {
                deleteChat(chat)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectModel)) { notification in
            if let model = notification.object as? ClaudeModel {
                selectedModel = model
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAPIKeySettings)) { _ in
            showingAPIKeySetup = true
        }
        .sheet(isPresented: $showingAPIKeySetup) {
            APIKeySetupView(isPresented: $showingAPIKeySetup) {
                needsAPIKey = false
            }
        }
        .sheet(isPresented: $needsAPIKey) {
            APIKeySetupView(isPresented: $needsAPIKey) {
                needsAPIKey = false
            }
            .interactiveDismissDisabled(true)
        }
        .task {
            // Check for API key FIRST, before anything else
            if !claudeService.hasAPIKey {
                needsAPIKey = true
            }
        }
    }
    
    private func friendlyTime(from date: Date) -> String {
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
    
    private var sortedChats: [ChatInfo] {
        chats.sorted { lhs, rhs in
            if lhs.isDefault { return true }
            if rhs.isDefault { return false }
            return lhs.lastUpdated > rhs.lastUpdated
        }
    }
    
    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        if messages.isEmpty {
                            Text("Chat messages will appear here")
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if let streamingId = streamingMessageId, !streamingContent.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("🧠")
                                        .font(.title2)
                                    
                                    MarkdownMessageView(content: streamingContent)
                                    
                                    Spacer()
                                }
                                .id(streamingId)
                            }
                            
                            if isLoading && streamingContent.isEmpty {
                                HStack {
                                    Text("🧠")
                                        .font(.title2)
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: streamingContent) { _, _ in
                    if let streamingId = streamingMessageId {
                        withAnimation {
                            proxy.scrollTo(streamingId, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            VStack(spacing: 4) {
                HStack {
                    Menu {
                        ForEach(ClaudeModel.allCases) { model in
                            Button {
                                selectedModel = model
                            } label: {
                                HStack {
                                    Text("\(model.emoji) \(model.displayName)")
                                    if selectedModel == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("\(selectedModel.emoji) \(selectedModel.displayName)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(totalInputTokens + totalOutputTokens) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("$\(calculateCost())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Clear Chat") {
                        clearCurrentChat()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                
                if errorMessage != nil {
                    HStack {
                        Text(errorMessage!)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            Divider()
            
            HStack(spacing: 12) {
                TextField("Type your message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...10)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .onSubmit {
                        sendMessage()
                    }
                
                Button("Send") {
                    sendMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle(selectedChat ?? "Select a chat")
    }
    
    // MARK: - Database Operations
    
    private func initializeDatabase() {
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
    
    private func loadAllChats() {
        do {
            chats = try dataService.loadAllChats()
        } catch {
            errorMessage = "Failed to load chats: \(error.localizedDescription)"
            print("Load chats error: \(error)")
        }
    }
    
    private func createNewChat() {
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
    
    private func deleteChat(_ chat: ChatInfo) {
        guard !chat.isDefault else { return }
        
        do {
            try dataService.deleteChat(chat.id)
            loadAllChats()
            
            if selectedChat == chat.id {
                selectedChat = "Scratch Pad"
            }
        } catch {
            errorMessage = "Failed to delete chat: \(error.localizedDescription)"
        }
    }
    
    private func loadChat(chatId: String) {
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
            
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load chat: \(error.localizedDescription)"
            print("Load Error: \(error)")
        }
    }
    
    private func clearCurrentChat() {
        guard let chatId = selectedChat else { return }
        
        do {
            try dataService.deleteChat(chatId)
            messages = []
            totalInputTokens = 0
            totalOutputTokens = 0
            
            let isDefault = chatId == "Scratch Pad"
            try dataService.saveMetadata(
                chatId: chatId,
                inputTokens: 0,
                outputTokens: 0,
                isDefault: isDefault
            )
            
            loadAllChats()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to clear chat: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Message Sending
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let chatId = selectedChat else { return }
        
        let userMessage = Message(
            role: .user,
            content: messageText,
            timestamp: Date()
        )
        
        messages.append(userMessage)
        
        do {
            try dataService.saveMessage(userMessage, chatId: chatId)
        } catch {
            print("Failed to save user message: \(error)")
        }
        
        messageText = ""
        errorMessage = nil
        
        let assistantMessageId = UUID()
        streamingMessageId = assistantMessageId
        streamingContent = ""
        isLoading = true
        
        Task {
            do {
                var fullResponse = ""
                var streamInputTokens = 0
                var streamOutputTokens = 0
                
                try await claudeService.streamMessage(
                    messages: messages,
                    model: selectedModel,
                    onChunk: { chunk in
                        streamingContent += chunk
                        fullResponse += chunk
                    },
                    onComplete: { inputTokens, outputTokens in
                        streamInputTokens = inputTokens
                        streamOutputTokens = outputTokens
                    }
                )
                
                totalInputTokens += streamInputTokens
                totalOutputTokens += streamOutputTokens
                
                let assistantMessage = Message(
                    id: assistantMessageId,
                    role: .assistant,
                    content: fullResponse,
                    timestamp: Date()
                )
                
                messages.append(assistantMessage)
                streamingMessageId = nil
                streamingContent = ""
                isLoading = false
                
                try dataService.saveMessage(assistantMessage, chatId: chatId)
                
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
                errorMessage = "Error: \(error.localizedDescription)"
                print("Claude API Error: \(error)")
            }
        }
    }
    
    private func calculateCost() -> String {
        let inputCost = Double(totalInputTokens) / 1_000_000.0 * selectedModel.inputCostPerMillion
        let outputCost = Double(totalOutputTokens) / 1_000_000.0 * selectedModel.outputCostPerMillion
        let totalCost = inputCost + outputCost
        return String(format: "%.4f", totalCost)
    }
}

// MARK: - Message Bubble View

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
            }
            
            if message.role == .assistant {
                Text("🧠")
                    .font(.title2)
            }
            
            if message.role == .assistant {
                MarkdownMessageView(content: message.content)
            } else {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
            }
            
            if message.role == .user {
                Text("😎")
                    .font(.title2)
            }
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - Markdown Message View

struct MarkdownMessageView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseContent(), id: \.id) { block in
                switch block.type {
                case .codeBlock(let language):
                    CodeBlockView(code: block.content, language: language)
                case .text:
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(block.content.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                            if line.isEmpty {
                                Spacer().frame(height: 8)
                            } else if let attributedString = try? AttributedString(markdown: line) {
                                Text(attributedString)
                                    .textSelection(.enabled)
                            } else {
                                Text(line)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func parseContent() -> [MessageContentBlock] {
        var blocks: [MessageContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeLanguage = ""
        var blockId = 0
        
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    if !codeBlockContent.isEmpty {
                        blocks.append(MessageContentBlock(
                            id: blockId,
                            type: .codeBlock(language: codeLanguage),
                            content: codeBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        blockId += 1
                    }
                    codeBlockContent = ""
                    codeLanguage = ""
                    inCodeBlock = false
                } else {
                    if !currentText.isEmpty {
                        blocks.append(MessageContentBlock(
                            id: blockId,
                            type: .text,
                            content: currentText.trimmingCharacters(in: .newlines)
                        ))
                        blockId += 1
                        currentText = ""
                    }
                    let languageStart = line.index(line.startIndex, offsetBy: 3)
                    codeLanguage = String(line[languageStart...]).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
            } else {
                if inCodeBlock {
                    codeBlockContent += line + "\n"
                } else {
                    currentText += line + "\n"
                }
            }
        }
        
        if !currentText.isEmpty {
            let trimmed = currentText.trimmingCharacters(in: .newlines)
            if !trimmed.isEmpty {
                blocks.append(MessageContentBlock(
                    id: blockId,
                    type: .text,
                    content: trimmed
                ))
            }
        }
        
        if !codeBlockContent.isEmpty {
            blocks.append(MessageContentBlock(
                id: blockId,
                type: .codeBlock(language: codeLanguage),
                content: codeBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        
        return blocks
    }
}

struct MessageContentBlock {
    let id: Int
    let type: BlockType
    let content: String
    
    enum BlockType {
        case text
        case codeBlock(language: String)
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !language.isEmpty {
                Text(language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}

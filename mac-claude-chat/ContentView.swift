//
//  ContentView.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif
struct ContentView: View {
    @State private var selectedChat: String? = "Scratch Pad"
    @State private var messageText: String = ""
    @State private var inputHeight: CGFloat = 36  // Dynamic input height
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
    @State private var selectedModel: ClaudeModel = .turbo  // TODO: Remove after TokenAuditView rework
    @State private var showingAPIKeySetup: Bool = false
    @State private var needsAPIKey: Bool = false
    @State private var toolActivityMessage: String?
    @State private var renamingChatId: String?
    @State private var renameChatText: String = ""
    @State private var showUnderConstruction: Bool = false
    @State private var pendingImages: [PendingImage] = []
    @State private var showingImagePicker: Bool = false
    @State private var contextThreshold: Int = 0  // Context management: grade threshold for filtering
    @State private var showingTokenAudit: Bool = false

    @Environment(\.modelContext) private var modelContext
    private let claudeService = ClaudeService()

    private var dataService: SwiftDataService {
        SwiftDataService(modelContext: modelContext)
    }

    private var systemPrompt: String {
        """
        You are Claude, an AI assistant in a natural conversation with Drew \
        (Andrew Killeen), a retired engineer and programmer in Catonsville, Maryland.

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
        Don't deflect with "I don't have real-time data" — search for it.
        IMPORTANT: Use all tools silently. Never announce that you are checking the date, time, weather, or searching. Just do it and weave the results into your response naturally.
        You can call multiple tools in a single response when needed.
        For weather queries with no specific location, default to Drew's location.

        TEMPORAL REFERENCES:
        When the user mentions any relative time ("last Sunday", "this week", \
        "yesterday", "recently", "the latest"), ALWAYS call get_datetime first \
        to anchor your reasoning to the actual current date before proceeding.
        Never assume you know today's date — always verify with the tool.
        Use tools silently — don't announce that you're checking the date, time, or weather. Just do it and incorporate the results naturally.

        ICEBERG TIP:
        At the very end of every response, append a one-line summary of this exchange \
        wrapped in an HTML comment marker. This summary captures the essence of what \
        was discussed or accomplished in this turn — it will be used for conversation \
        context in future turns. Format:
        <!--tip:Brief summary of what was discussed or accomplished-->
        Keep tips under 20 words. Examples:
        <!--tip:Greeted user, casual check-in-->
        <!--tip:Explained SwiftData CloudKit constraints and migration strategy-->
        <!--tip:Provided weather for Catonsville, clear skies 44°F-->
        """
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Chats")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        showingNewChatDialog = true
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                List(sortedChats, id: \.id, selection: $selectedChat) { chat in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.name)
                            Text(friendlyTime(from: chat.lastUpdated))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Menu {
                            if !chat.isDefault {
                                Button {
                                    renamingChatId = chat.id
                                    renameChatText = chat.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                            }

                            Button {
                                showUnderConstruction = true
                            } label: {
                                Label("Star", systemImage: "star")
                            }

                            Button {
                                showUnderConstruction = true
                            } label: {
                                Label("Add to Project", systemImage: "folder")
                            }

                            Button {
                                publishChat(chatId: chat.id)
                            } label: {
                                Label("Publish…", systemImage: "arrow.up.doc")
                            }

                            if !chat.isDefault {
                                Divider()
                                Button(role: .destructive) {
                                    deleteChat(chat)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
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
            if claudeService.hasAPIKey {
                initializeDatabase()
            }
        }
        .onChange(of: needsAPIKey) { oldValue, newValue in
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
        .alert("Rename Chat", isPresented: Binding(
            get: { renamingChatId != nil },
            set: { if !$0 { renamingChatId = nil } }
        )) {
            TextField("Chat Name", text: $renameChatText)
            Button("Cancel", role: .cancel) {
                renamingChatId = nil
                renameChatText = ""
            }
            Button("Rename") {
                renameCurrentChat()
            }
            .disabled(renameChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a new name for the chat")
        }
        .alert("Under Construction", isPresented: $showUnderConstruction) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This feature is coming soon.")
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
        .onReceive(NotificationCenter.default.publisher(for: .showAPIKeySettings)) { _ in
            showingAPIKeySetup = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .publishChat)) { _ in
            if let chatId = selectedChat {
                publishChat(chatId: chatId)
            }
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
        .sheet(isPresented: $showingTokenAudit) {
            TokenAuditView(messages: messages, model: selectedModel)
        }

        .task {
            if !claudeService.hasAPIKey {
                needsAPIKey = true
            }
        }
    }

    // MARK: - Helpers

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

    private func publishChat(chatId: String) {
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
            // Defer panel presentation to escape SwiftUI's update cycle
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

    private var sortedChats: [ChatInfo] {
        chats.sorted { lhs, rhs in
            if lhs.isDefault { return true }
            if rhs.isDefault { return false }
            return lhs.lastUpdated > rhs.lastUpdated
        }
    }

    /// Calculate total session cost by summing actual per-message costs
    private func calculateCost() -> String {
        var totalCost = 0.0
        for message in messages where message.role == .assistant && !message.modelUsed.isEmpty {
            if let model = ClaudeModel(rawValue: message.modelUsed) {
                totalCost += Double(message.inputTokens) / 1_000_000.0 * model.inputCostPerMillion
                totalCost += Double(message.outputTokens) / 1_000_000.0 * model.outputCostPerMillion
            }
        }
        return String(format: "%.4f", totalCost)
    }

    // MARK: - Chat Detail View

    private var chatView: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Drew's Claude Chat")
                    .font(.headline)

                Spacer()

                if let chatName = selectedChat {
                    Text(chatName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PlatformColor.windowBackground.opacity(0.8))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        if messages.isEmpty {
                            Text("Chat messages will appear here")
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                // For turn-based dimming: all messages in a turn share the user message's grade
                                // Use turnId when available, fall back to position-based lookup for legacy messages
                                let turnGrade: Int = {
                                    if message.role == .user {
                                        return message.textGrade
                                    } else {
                                        // Try to find user message with same turnId first
                                        if !message.turnId.isEmpty {
                                            if let userMsg = messages.first(where: { $0.turnId == message.turnId && $0.role == .user }) {
                                                return userMsg.textGrade
                                            }
                                        }
                                        // Fall back to position-based lookup for legacy messages without turnId
                                        for i in stride(from: index - 1, through: 0, by: -1) {
                                            if messages[i].role == .user {
                                                return messages[i].textGrade
                                            }
                                        }
                                        return message.textGrade  // Fallback
                                    }
                                }()

                                MessageBubble(
                                    message: message,
                                    turnGrade: turnGrade,
                                    threshold: contextThreshold,
                                    onGradeChange: { newGrade in
                                        updateMessageGrade(messageId: message.id, grade: newGrade)
                                    },
                                    onCopyTurn: {
                                        copyTurn(for: message)
                                    }
                                )
                                .id(message.id)
                            }

                            if let streamingId = streamingMessageId, !streamingContent.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("🧠")
                                        .font(.body)

                                    MarkdownMessageView(content: streamingContent)

                                    Spacer()
                                }
                                .id(streamingId)
                            }

                            if let toolMessage = toolActivityMessage {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(toolMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                    Spacer()
                                }
                                .padding(.leading, 36)
                                .id("tool-activity-indicator")
                            }

                            if isLoading && streamingContent.isEmpty && toolActivityMessage == nil {
                                HStack {
                                    Text("🧠")
                                        .font(.body)
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                    Spacer()
                                }
                                .id("thinking-indicator")
                            }

                            // Bottom spacer for breathing room above input bar
                            Color.clear
                                .frame(height: 24)
                                .id("bottom-spacer")
                        }
                    }
                    .padding()
                    .frame(maxWidth: 720, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if messages.last != nil {
                        // Small delay to allow SwiftUI to lay out the new message
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo("bottom-spacer", anchor: .bottom)
                            }
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
                .onChange(of: isLoading) { _, newValue in
                    if newValue {
                        // Scroll to thinking indicator when loading starts
                        // Small delay to allow SwiftUI to render the indicator first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation {
                                proxy.scrollTo("thinking-indicator", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: toolActivityMessage) { _, newValue in
                    if newValue != nil {
                        // Scroll to tool activity indicator when it appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo("tool-activity-indicator", anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            VStack(spacing: 4) {
                HStack {
                    Button {
                        showingTokenAudit = true
                    } label: {
                        Text("\(totalInputTokens + totalOutputTokens) tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View per-turn token audit")

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("$\(calculateCost())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Context threshold - tappable cycling number
                    Button {
                        // Cycle 0→1→2→3→4→5→0
                        let newValue = (contextThreshold + 1) % 6
                        contextThreshold = newValue
                        updateContextThreshold(newValue)
                    } label: {
                        Text("Context: \(contextThreshold)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(contextThreshold > 0 ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Tap to cycle threshold (0-5). Turns with grade < \(contextThreshold) are excluded from context.")

                    Spacer()

                    // Bulk grade actions
                    Menu {
                        Button("Grade All 5 (Full Context)") {
                            confirmBulkGrade(grade: 5)
                        }
                        Button("Grade All 0 (Clear Context)") {
                            confirmBulkGrade(grade: 0)
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Bulk grade actions")

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

            VStack(spacing: 8) {
                // Pending images preview strip
                if !pendingImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pendingImages) { pending in
                                PendingImageThumbnail(
                                    pending: pending,
                                    onRemove: { removePendingImage(id: pending.id) }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 70)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    // Attachment button
                    Button {
                        showingImagePicker = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("Attach image")

                    ZStack(alignment: .topLeading) {
                        #if os(macOS)
                        // macOS: Use NSTextView wrapper for proper spell checking
                        SpellCheckingTextEditor(
                            text: $messageText,
                            contentHeight: $inputHeight,
                            onReturn: { sendMessage() },
                            onImagePaste: { imageData in
                                addImageFromData(imageData)
                            },
                            onTextFileDrop: { text in
                                messageText += text
                            }
                        )
                        .frame(height: min(max(inputHeight, 36), 200))
                        #else
                        // iOS: Use hidden Text to measure content height, then size TextEditor
                        Text(messageText.isEmpty ? " " : messageText)
                            .font(.body)
                            .padding(6)
                            .opacity(0)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: InputHeightPreferenceKey.self,
                                        value: geometry.size.height
                                    )
                                }
                            )
                            .onPreferenceChange(InputHeightPreferenceKey.self) { height in
                                inputHeight = max(36, height)
                            }

                        TextEditor(text: $messageText)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(height: min(max(inputHeight, 36), 200))
                        #endif

                        // Placeholder text overlay
                        // Padding must match NSTextView's textContainerInset (width: 4, height: 8)
                        // plus the text container's lineFragmentPadding (default 5pt on each side)
                        if messageText.isEmpty && pendingImages.isEmpty {
                            Text("Type your message...")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 9)  // 4 (inset) + 5 (lineFragmentPadding)
                                .padding(.top, 8)      // matches textContainerInset.height
                                .allowsHitTesting(false)
                        }
                    }
                    .background(PlatformColor.textBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.15), value: inputHeight)
                    .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                        handleImageDrop(providers: providers)
                        return true
                    }

                    Button("Send") {
                        sendMessage()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingImages.isEmpty) || isLoading)
                }
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
            .fileImporter(
                isPresented: $showingImagePicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result: result)
            }
        }
    }

    // MARK: - Database Operations

    private func initializeDatabase() {
        // CloudKit: merge any duplicate sessions from multi-device creation
        do {
            try dataService.deduplicateSessions()
        } catch {
            print("Deduplication check: \(error)")
        }

        // Backfill turnIds for messages created before turn tracking
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

    private func renameCurrentChat() {
        guard let oldId = renamingChatId else { return }
        let newName = renameChatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }

        do {
            try dataService.renameChat(from: oldId, to: newName)
            loadAllChats()

            // Update selection if this was the selected chat
            if selectedChat == oldId {
                selectedChat = newName
            }

            renamingChatId = nil
            renameChatText = ""
        } catch {
            errorMessage = "Failed to rename chat: \(error.localizedDescription)"
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

            // Load context threshold for this chat
            contextThreshold = dataService.getContextThreshold(forChat: chatId)

            errorMessage = nil
        } catch {
            errorMessage = "Failed to load chat: \(error.localizedDescription)"
            print("Load Error: \(error)")
        }
    }

    // MARK: - Context Management

    private func updateContextThreshold(_ newValue: Int) {
        guard let chatId = selectedChat else { return }

        do {
            try dataService.setContextThreshold(forChat: chatId, threshold: newValue)
        } catch {
            errorMessage = "Failed to update threshold: \(error.localizedDescription)"
        }
    }

    private func confirmBulkGrade(grade: Int) {
        guard let chatId = selectedChat else { return }

        do {
            try dataService.setAllGrades(forChat: chatId, textGrade: grade, imageGrade: grade)
            // Reload to refresh UI
            loadChat(chatId: chatId)
        } catch {
            errorMessage = "Failed to update grades: \(error.localizedDescription)"
        }
    }

    private func updateMessageGrade(messageId: UUID, grade: Int) {
        do {
            try dataService.setTextGrade(forMessageId: messageId.uuidString, grade: grade)
            // Update local state to reflect change immediately
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].textGrade = grade
                messages[index].imageGrade = grade  // Images inherit text grade for now
            }
        } catch {
            errorMessage = "Failed to update grade: \(error.localizedDescription)"
        }
    }

    /// Copy both user and assistant messages for a given turn to clipboard
    private func copyTurn(for message: Message) {
        // Find all messages in this turn
        let turnMessages: [Message]
        if !message.turnId.isEmpty {
            turnMessages = messages.filter { $0.turnId == message.turnId && $0.isFinalResponse }
        } else {
            // Legacy messages without turnId: find the user+assistant pair by position
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                var pair: [Message] = []
                if message.role == .user {
                    pair.append(message)
                    if index + 1 < messages.count && messages[index + 1].role == .assistant {
                        pair.append(messages[index + 1])
                    }
                } else {
                    // Assistant: look back for user
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

        // Build clean text
        var parts: [String] = []
        for msg in turnMessages.sorted(by: { $0.timestamp < $1.timestamp }) {
            let cleaned = stripAllMarkers(from: msg.content)
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

    /// Gets messages filtered by the current threshold for API calls
    /// Turns are user+assistant pairs; if user message's textGrade < threshold, the whole turn is excluded
    private func getFilteredMessagesForAPI(threshold: Int, excludingLast: Bool) async -> [Message] {
        guard let chatId = selectedChat else { return [] }

        do {
            let messagesWithGrades = try dataService.getMessagesWithGrades(forChat: chatId)
            var filtered: [Message] = []
            var i = 0
            let count = excludingLast ? messagesWithGrades.count - 1 : messagesWithGrades.count

            while i < count {
                let item = messagesWithGrades[i]

                // Skip intermediate tool loop messages (only include final responses)
                // This prunes tool_use/tool_result exchanges from previous turns
                guard item.isFinalResponse else {
                    i += 1
                    continue
                }

                if item.message.role == .user {
                    // Check if this user message meets threshold
                    if item.textGrade >= threshold {
                        // Include user message
                        filtered.append(item.message)
                        // Include following assistant message if it's a final response and present
                        if i + 1 < count && messagesWithGrades[i + 1].message.role == .assistant {
                            // Only include if it's the final response for this turn
                            if messagesWithGrades[i + 1].isFinalResponse {
                                filtered.append(messagesWithGrades[i + 1].message)
                            }
                            i += 2
                            continue
                        }
                    } else {
                        // Skip this turn entirely (user + assistant if present)
                        if i + 1 < count && messagesWithGrades[i + 1].message.role == .assistant {
                            i += 2
                            continue
                        }
                    }
                }
                i += 1
            }

            return filtered
        } catch {
            print("Failed to get filtered messages: \(error)")
            return []
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

        // Build persisted content with markers prepended
        let markerPrefix = imageMarkers.isEmpty ? "" : imageMarkers.joined(separator: "\n") + "\n"
        let persistedContent = markerPrefix + trimmedText

        // Capture pending images for API call before clearing
        let imagesToSend = pendingImages

        // Generate a turnId for this conversation turn
        let turnId = UUID().uuidString

        let userMessage = Message(
            role: .user,
            content: persistedContent,
            timestamp: Date(),
            turnId: turnId,
            isFinalResponse: true  // User messages are always "final"
        )

        messages.append(userMessage)

        do {
            // New messages always get grade 5 (default)
            try dataService.saveMessage(userMessage, chatId: chatId, turnId: turnId, isFinalResponse: true)
        } catch {
            print("Failed to save user message: \(error)")
        }

        messageText = ""
        pendingImages = []
        inputHeight = 36  // Reset input height
        errorMessage = nil

        let assistantMessageId = UUID()
        streamingMessageId = assistantMessageId
        streamingContent = ""
        toolActivityMessage = nil
        isLoading = true

        // Capture threshold at send time for consistent filtering across tool loop
        let sendThreshold = contextThreshold

        Task {
            do {
                // --- Model Selection ---
                let effectiveModel: ClaudeModel
                let messageForAPI: String

                switch parseResult {
                case .builtIn(let command, let remainder) where command.isPassthrough:
                    // Slash command model override — skip router
                    effectiveModel = command.forcedModel ?? .fast
                    messageForAPI = remainder.isEmpty ? trimmedText : remainder
                    print("🤖 Slash command: /\(command.rawValue) → \(effectiveModel.displayName)")
                default:
                    // Normal two-tier routing
                    let tips = RouterService.collectTips(from: messages)
                    let classification = await RouterService.classify(
                        userMessage: trimmedText,
                        tips: tips,
                        claudeService: claudeService
                    )
                    effectiveModel = classification.model
                    messageForAPI = trimmedText
                }

                // Build API messages filtered by grade threshold
                // Grade filtering happens here - messages with textGrade < threshold are excluded
                let filteredMessages = await getFilteredMessagesForAPI(threshold: sendThreshold, excludingLast: true)
                var apiMessages: [[String: Any]] = filteredMessages.map { msg in
                    buildAPIMessage(from: msg)
                }

                // Build current user message with proper image handling
                var currentMessageContent: [[String: Any]] = []

                // Add image blocks first
                for pending in imagesToSend {
                    currentMessageContent.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": pending.mediaType,
                            "data": pending.base64Data
                        ]
                    ])
                }

                // Add text block if there's text
                if !messageForAPI.isEmpty {
                    currentMessageContent.append([
                        "type": "text",
                        "text": messageForAPI
                    ])
                }

                // Add current message to apiMessages
                if currentMessageContent.isEmpty {
                    // Shouldn't happen due to guard above, but fallback
                    apiMessages.append(["role": "user", "content": messageForAPI])
                } else if currentMessageContent.count == 1 && imagesToSend.isEmpty {
                    // Text only - can use simple string format
                    apiMessages.append(["role": "user", "content": messageForAPI])
                } else {
                    // Mixed content - use content blocks
                    apiMessages.append(["role": "user", "content": currentMessageContent])
                }

                let tools = ToolService.toolDefinitions
                var fullResponse = ""
                var totalStreamInputTokens = 0
                var totalStreamOutputTokens = 0
                var iteration = 0
                let maxIterations = 5
                var collectedMarkers: [String] = []

                while iteration < maxIterations {
                    iteration += 1

                    let result = try await claudeService.streamMessageWithTools(
                        messages: apiMessages,
                        model: effectiveModel,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        onTextChunk: { chunk in
                            streamingContent += chunk
                            fullResponse += chunk
                        }
                    )

                    totalStreamInputTokens += result.inputTokens
                    totalStreamOutputTokens += result.outputTokens

                    if result.stopReason == "end_turn" || result.toolCalls.isEmpty {
                        break
                    }

                    var assistantContent: [[String: Any]] = []
                    if !result.textContent.isEmpty {
                        assistantContent.append(["type": "text", "text": result.textContent])
                    }
                    for toolCall in result.toolCalls {
                        assistantContent.append([
                            "type": "tool_use",
                            "id": toolCall.id,
                            "name": toolCall.name,
                            "input": toolCall.input
                        ])
                    }
                    apiMessages.append(["role": "assistant", "content": assistantContent])

                    var toolResults: [[String: Any]] = []
                    for toolCall in result.toolCalls {
                        let displayName: String
                        switch toolCall.name {
                        case "search_web":
                            let query = toolCall.input["query"] as? String ?? ""
                            displayName = "🔍 Searching: \(query)"
                        case "get_weather":
                            let location = toolCall.input["location"] as? String ?? "Catonsville"
                            displayName = "🌤️ Getting weather for \(location)"
                        case "get_datetime":
                            displayName = "🕐 Checking date/time"
                        default:
                            displayName = "🔧 Using \(toolCall.name)"
                        }
                        await MainActor.run {
                            toolActivityMessage = displayName
                        }

                        let toolResult = await ToolService.executeTool(
                            name: toolCall.name,
                            input: toolCall.input
                        )
                        // Send plain text to Claude
                        toolResults.append([
                            "type": "tool_result",
                            "tool_use_id": toolCall.id,
                            "content": toolResult.textForLLM
                        ])
                        // Collect any embedded markers for later
                        if let marker = toolResult.embeddedMarker {
                            collectedMarkers.append(marker)
                        }
                    }

                    apiMessages.append(["role": "user", "content": toolResults])

                    await MainActor.run {
                        toolActivityMessage = nil
                        if !fullResponse.isEmpty {
                            streamingContent += "\n\n"
                            fullResponse += "\n\n"
                        }
                    }
                }

                totalInputTokens += totalStreamInputTokens
                totalOutputTokens += totalStreamOutputTokens

                // Extract iceberg tip from response before saving
                let (cleanedResponse, extractedTip) = RouterService.extractTip(from: fullResponse)

                // Prepend any collected markers to the saved message content
                let markerPrefix = collectedMarkers.isEmpty ? "" : collectedMarkers.joined(separator: "\n") + "\n"
                let assistantMessage = Message(
                    id: assistantMessageId,
                    role: .assistant,
                    content: markerPrefix + cleanedResponse,
                    timestamp: Date(),
                    turnId: turnId,
                    isFinalResponse: true,  // This is the final response for this turn
                    inputTokens: totalStreamInputTokens,
                    outputTokens: totalStreamOutputTokens,
                    icebergTip: extractedTip ?? "",
                    modelUsed: effectiveModel.rawValue
                )

                messages.append(assistantMessage)
                streamingMessageId = nil
                streamingContent = ""

                // Log the iceberg tip if generated
                if let tip = extractedTip {
                    print("🏔️ Tip: \(tip)")
                }
                toolActivityMessage = nil
                isLoading = false

                // Assistant messages inherit grade from their turn's user message (default 5)
                // Persist per-turn token counts for the audit view
                try dataService.saveMessage(assistantMessage, chatId: chatId, turnId: turnId, isFinalResponse: true, inputTokens: totalStreamInputTokens, outputTokens: totalStreamOutputTokens)

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

    // MARK: - Image Attachment Helpers

    /// Add image from raw data (from paste or file)
    private func addImageFromData(_ data: Data) {
        guard let processed = ImageProcessor.process(data) else {
            print("Failed to process image")
            return
        }

        // Create thumbnail for preview (use original data if small enough, otherwise use processed)
        let thumbnailData = data.count < 100_000 ? data : Data(base64Encoded: processed.base64Data) ?? data

        let pending = PendingImage(
            id: processed.id,
            base64Data: processed.base64Data,
            mediaType: processed.mediaType,
            thumbnailData: thumbnailData
        )

        pendingImages.append(pending)
    }

    /// Remove a pending image by ID
    private func removePendingImage(id: UUID) {
        pendingImages.removeAll { $0.id == id }
    }

    /// Handle drag and drop of images
    private func handleImageDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // Try file URL first (most common for Finder drops)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url else {
                        print("Drop: Failed to load URL - \(error?.localizedDescription ?? "unknown")")
                        return
                    }

                    // Check if it's an image file
                    guard let typeIdentifier = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                          let uti = UTType(typeIdentifier),
                          uti.conforms(to: .image) else {
                        print("Drop: Not an image file")
                        return
                    }

                    // Read the image data
                    guard let imageData = try? Data(contentsOf: url) else {
                        print("Drop: Failed to read image data from \(url)")
                        return
                    }

                    DispatchQueue.main.async {
                        self.addImageFromData(imageData)
                    }
                }
            }
            // Fallback: try to load as raw image data
            else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let data = data {
                        DispatchQueue.main.async {
                            self.addImageFromData(data)
                        }
                    }
                }
            }
        }
    }

    /// Handle file importer result
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                if let imageData = try? Data(contentsOf: url) {
                    addImageFromData(imageData)
                }
            }
        case .failure(let error):
            print("File import error: \(error)")
        }
    }

    /// Build API message format from a stored Message
    /// Converts image markers to placeholder text (images already analyzed by Claude)
    /// Note: This function is only called for PAST messages in conversation history.
    /// Current-turn images are handled separately with full base64 data.
    private func buildAPIMessage(from message: Message) -> [String: Any] {
        let role = message.role == .user ? "user" : "assistant"

        // Check for image markers in user messages
        if message.role == .user {
            let (images, cleanText) = parseImageMarkers(from: message.content)

            if !images.isEmpty {
                // Past images: replace with lightweight placeholder to save tokens
                // (base64 images can be 10,000-50,000+ tokens each)
                var contentBlocks: [[String: Any]] = []

                contentBlocks.append([
                    "type": "text",
                    "text": "[Image previously shared and analyzed]"
                ])

                // Add text block if there's text
                let trimmedText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    contentBlocks.append([
                        "type": "text",
                        "text": trimmedText
                    ])
                }

                return ["role": role, "content": contentBlocks]
            }
        }

        // For assistant messages or user messages without images, use simple string content
        // Strip any markers from assistant messages (weather, etc.) for the API
        let cleanContent = stripAllMarkers(from: message.content)
        return ["role": role, "content": cleanContent]
    }

    /// Parse image markers from message content
    /// Returns array of image data and the cleaned text content
    private func parseImageMarkers(from content: String) -> (images: [(id: String, mediaType: String, base64Data: String)], cleanText: String) {
        var images: [(id: String, mediaType: String, base64Data: String)] = []
        var cleanContent = content

        let pattern = "<!--image:(\\{.+?\\})-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (images, content)
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches {
            if let jsonRange = Range(match.range(at: 1), in: content) {
                let jsonString = String(content[jsonRange])
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
                   let id = json["id"],
                   let mediaType = json["media_type"],
                   let base64Data = json["data"] {
                    images.append((id: id, mediaType: mediaType, base64Data: base64Data))
                }
            }
        }

        // Remove markers from content
        cleanContent = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
        // Clean up any leading newlines from marker removal
        cleanContent = cleanContent.trimmingCharacters(in: .whitespacesAndNewlines)

        return (images, cleanContent)
    }

    /// Strip all embedded markers (weather, image, etc.) from content
    private func stripAllMarkers(from content: String) -> String {
        var result = content

        // Strip weather markers
        if let regex = try? NSRegularExpression(pattern: "<!--weather:.+?-->\\n?", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Strip image markers
        if let regex = try? NSRegularExpression(pattern: "<!--image:\\{.+?\\}-->\\n?", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Strip iceberg tip markers
        if let regex = try? NSRegularExpression(pattern: "<!--tip:.+?-->\\n?", options: [.dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    ContentView()
        #if os(macOS)
        .frame(width: 900, height: 600)
        #endif
}

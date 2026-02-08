//
//  ContentView.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//

import SwiftUI
import SwiftData

// MARK: - Platform Colors

enum PlatformColor {
    static var windowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    static var textBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}

// MARK: - Input Height Preference Key (for iOS auto-sizing)

struct InputHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 36
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Spell-Checking Text Editor

#if os(macOS)
/// NSTextView wrapper that enables spell checking on macOS
/// (SwiftUI's TextEditor has a known bug where spell checking doesn't work)
struct SpellCheckingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var onReturn: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.autoresizingMask = [.width]

        // Enable spell checking
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false  // Show red underlines, don't auto-correct

        textView.allowsUndo = true
        textView.string = text

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Calculate initial height
        DispatchQueue.main.async {
            context.coordinator.updateContentHeight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            // Update height when text is set externally (e.g., cleared after send)
            DispatchQueue.main.async {
                context.coordinator.updateContentHeight()
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpellCheckingTextEditor
        weak var textView: NSTextView?

        init(_ parent: SpellCheckingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateContentHeight()
        }

        func updateContentHeight() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            // Ensure layout is complete
            layoutManager.ensureLayout(for: textContainer)

            // Get the used rect for the text
            let usedRect = layoutManager.usedRect(for: textContainer)

            // Add text container inset (top + bottom = 8 + 8 = 16)
            let totalHeight = usedRect.height + textView.textContainerInset.height * 2

            // Update the binding
            DispatchQueue.main.async {
                self.parent.contentHeight = max(36, totalHeight)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle Return key to send message (Shift+Return inserts newline)
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                let shiftPressed = event?.modifierFlags.contains(.shift) ?? false
                let optionPressed = event?.modifierFlags.contains(.option) ?? false

                if !shiftPressed && !optionPressed {
                    // Plain Return: send message
                    parent.onReturn?()
                    return true  // We handled it
                }
                // Shift+Return or Option+Return: let it insert a newline
                return false
            }
            return false
        }
    }
}
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
    @State private var selectedModel: ClaudeModel = .turbo
    @State private var showingAPIKeySetup: Bool = false
    @State private var needsAPIKey: Bool = false
    @State private var toolActivityMessage: String?
    @State private var renamingChatId: String?
    @State private var renameChatText: String = ""
    @State private var showUnderConstruction: Bool = false

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
        You can call multiple tools in a single response when needed.
        For weather queries with no specific location, default to Drew's location.
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
    
    private var sortedChats: [ChatInfo] {
        chats.sorted { lhs, rhs in
            if lhs.isDefault { return true }
            if rhs.isDefault { return false }
            return lhs.lastUpdated > rhs.lastUpdated
        }
    }
    
    private func calculateCost() -> String {
        let inputCost = Double(totalInputTokens) / 1_000_000.0 * selectedModel.inputCostPerMillion
        let outputCost = Double(totalOutputTokens) / 1_000_000.0 * selectedModel.outputCostPerMillion
        let totalCost = inputCost + outputCost
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
                
                Text("\(selectedModel.emoji) \(selectedModel.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
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
                            ForEach(messages) { message in
                                MessageBubble(message: message)
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
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: 720, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollDismissesKeyboard(.interactively)
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
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    #endif
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
            
            HStack(alignment: .bottom, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    #if os(macOS)
                    // macOS: Use NSTextView wrapper for proper spell checking
                    SpellCheckingTextEditor(text: $messageText, contentHeight: $inputHeight) {
                        sendMessage()
                    }
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
                    if messageText.isEmpty {
                        Text("Type your message...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 14)
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
    }
    
    // MARK: - Database Operations
    
    private func initializeDatabase() {
        // CloudKit: merge any duplicate sessions from multi-device creation
        do {
            try dataService.deduplicateSessions()
        } catch {
            print("Deduplication check: \(error)")
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
        toolActivityMessage = nil
        isLoading = true

        Task {
            do {
                var apiMessages: [[String: Any]] = messages.map { msg in
                    [
                        "role": msg.role == .user ? "user" : "assistant",
                        "content": msg.content
                    ]
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
                        model: selectedModel,
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

                // Prepend any collected markers to the saved message content
                let markerPrefix = collectedMarkers.isEmpty ? "" : collectedMarkers.joined(separator: "\n") + "\n"
                let assistantMessage = Message(
                    id: assistantMessageId,
                    role: .assistant,
                    content: markerPrefix + fullResponse,
                    timestamp: Date()
                )

                messages.append(assistantMessage)
                streamingMessageId = nil
                streamingContent = ""
                toolActivityMessage = nil
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
                toolActivityMessage = nil
                errorMessage = "Error: \(error.localizedDescription)"
                print("Claude API Error: \(error)")
            }
        }
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
                    .font(.body)
            }
            
            if message.role == .assistant {
                MarkdownMessageView(content: message.content)
            } else {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
            }
            
            if message.role == .user {
                Text("😎")
                    .font(.body)
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

    /// Parsed weather data from embedded markers
    private var weatherData: [WeatherData] {
        var results: [WeatherData] = []
        let pattern = "<!--weather:(.+?)-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return results
        }
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        for match in matches {
            if let jsonRange = Range(match.range(at: 1), in: content) {
                let jsonString = String(content[jsonRange])
                if let jsonData = jsonString.data(using: .utf8),
                   let data = try? JSONDecoder().decode(WeatherData.self, from: jsonData) {
                    results.append(data)
                }
            }
        }
        return results
    }

    /// Content with markers stripped out
    private var cleanedContent: String {
        let pattern = "<!--weather:.+?-->\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Render weather cards first
            ForEach(Array(weatherData.enumerated()), id: \.offset) { _, data in
                WeatherCardView(data: data)
            }

            // Then render the text content
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
                                Text(styleInlineCode(attributedString))
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
        .lineSpacing(4)
    }
    
    private func parseContent() -> [MessageContentBlock] {
        var blocks: [MessageContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeLanguage = ""
        var blockId = 0

        // Use cleaned content (markers stripped)
        let lines = cleanedContent.components(separatedBy: "\n")
        
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
    
    /// Enhances inline code spans with visible background styling
    private func styleInlineCode(_ input: AttributedString) -> AttributedString {
        var result = input
        
        // Find runs with inline code presentation intent and style them
        for run in result.runs {
            if let inlineIntent = run.inlinePresentationIntent, inlineIntent.contains(.code) {
                let range = run.range
                result[range].font = .system(.body, design: .monospaced)
                result[range].backgroundColor = Color.gray.opacity(0.2)
            }
        }
        
        return result
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

// MARK: - Syntax Highlighter

/// Regex-based syntax highlighter for code blocks
/// Supports Python, Swift, JavaScript/TypeScript, JSON, Bash, and generic fallback
enum SyntaxHighlighter {
    
    // MARK: - Color Palette (Dracula-inspired for dark backgrounds)
    
    static let keyword = Color(red: 1.0, green: 0.475, blue: 0.776)      // Pink #FF79C6
    static let string = Color(red: 0.314, green: 0.98, blue: 0.482)      // Green #50FA7B
    static let comment = Color(red: 0.384, green: 0.447, blue: 0.643)    // Gray #6272A4
    static let number = Color(red: 1.0, green: 0.722, blue: 0.424)       // Orange #FFB86C
    static let type = Color(red: 0.545, green: 0.914, blue: 0.992)       // Cyan #8BE9FD
    static let function = Color(red: 0.4, green: 0.85, blue: 0.937)      // Blue #66D9EF
    static let decorator = Color(red: 0.945, green: 0.98, blue: 0.549)   // Yellow #F1FA8C
    static let defaultText = Color(red: 0.973, green: 0.973, blue: 0.949) // Light #F8F8F2
    
    // MARK: - Language Detection
    
    enum Language {
        case python, swift, javascript, json, bash, generic
    }
    
    static func detectLanguage(_ hint: String) -> Language {
        switch hint.lowercased() {
        case "python", "py": return .python
        case "swift": return .swift
        case "javascript", "js", "typescript", "ts", "jsx", "tsx": return .javascript
        case "json": return .json
        case "bash", "sh", "shell", "zsh": return .bash
        default: return .generic
        }
    }
    
    // MARK: - Main Highlighting Entry Point
    
    static func highlight(_ code: String, language: String) -> AttributedString {
        let lang = detectLanguage(language)
        var result = AttributedString()
        
        let lines = code.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            result.append(highlightLine(line, language: lang))
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        
        return result
    }
    
    // MARK: - Line-by-Line Highlighting
    
    private static func highlightLine(_ line: String, language: Language) -> AttributedString {
        // Start with default-colored text
        var attributed = AttributedString(line)
        attributed.foregroundColor = defaultText
        
        guard !line.isEmpty else { return attributed }
        
        // Build token ranges with their colors
        var tokens: [(range: Range<String.Index>, color: Color)] = []
        
        // Apply patterns based on language
        switch language {
        case .python:
            tokens.append(contentsOf: findComments(in: line, style: .hash))
            tokens.append(contentsOf: findStrings(in: line, includeTripleQuotes: true))
            tokens.append(contentsOf: findDecorators(in: line, prefix: "@"))
            tokens.append(contentsOf: findKeywords(in: line, keywords: pythonKeywords))
            tokens.append(contentsOf: findNumbers(in: line))
            tokens.append(contentsOf: findTypes(in: line))
            tokens.append(contentsOf: findFunctionCalls(in: line))
            
        case .swift:
            tokens.append(contentsOf: findComments(in: line, style: .slashSlash))
            tokens.append(contentsOf: findStrings(in: line, includeTripleQuotes: true))
            tokens.append(contentsOf: findDecorators(in: line, prefix: "@"))
            tokens.append(contentsOf: findKeywords(in: line, keywords: swiftKeywords))
            tokens.append(contentsOf: findNumbers(in: line))
            tokens.append(contentsOf: findTypes(in: line))
            tokens.append(contentsOf: findFunctionCalls(in: line))
            
        case .javascript:
            tokens.append(contentsOf: findComments(in: line, style: .slashSlash))
            tokens.append(contentsOf: findStrings(in: line, includeTripleQuotes: false))
            tokens.append(contentsOf: findTemplateStrings(in: line))
            tokens.append(contentsOf: findKeywords(in: line, keywords: jsKeywords))
            tokens.append(contentsOf: findNumbers(in: line))
            tokens.append(contentsOf: findTypes(in: line))
            tokens.append(contentsOf: findFunctionCalls(in: line))
            
        case .json:
            tokens.append(contentsOf: findJsonKeys(in: line))
            tokens.append(contentsOf: findStrings(in: line, includeTripleQuotes: false))
            tokens.append(contentsOf: findNumbers(in: line))
            tokens.append(contentsOf: findKeywords(in: line, keywords: ["true", "false", "null"]))
            
        case .bash:
            tokens.append(contentsOf: findComments(in: line, style: .hash))
            tokens.append(contentsOf: findStrings(in: line, includeTripleQuotes: false))
            tokens.append(contentsOf: findBashVariables(in: line))
            tokens.append(contentsOf: findKeywords(in: line, keywords: bashKeywords))
            
        case .generic:
            tokens.append(contentsOf: findComments(in: line, style: .any))
            tokens.append(contentsOf: findStrings(in: line, includeTripleQuotes: false))
            tokens.append(contentsOf: findNumbers(in: line))
        }
        
        // Sort tokens by start position (earlier first), then by length (longer first for overlaps)
        let sortedTokens = tokens.sorted { a, b in
            if a.range.lowerBound != b.range.lowerBound {
                return a.range.lowerBound < b.range.lowerBound
            }
            return line.distance(from: a.range.lowerBound, to: a.range.upperBound) >
                   line.distance(from: b.range.lowerBound, to: b.range.upperBound)
        }
        
        // Apply colors, skipping overlapping ranges
        var coveredRanges: [Range<String.Index>] = []
        
        for token in sortedTokens {
            // Check if this range overlaps with any already-covered range
            let overlaps = coveredRanges.contains { covered in
                token.range.overlaps(covered)
            }
            
            if !overlaps {
                // Convert String.Index range to AttributedString range
                if let attrRange = Range(token.range, in: attributed) {
                    attributed[attrRange].foregroundColor = token.color
                }
                coveredRanges.append(token.range)
            }
        }
        
        return attributed
    }
    
    // MARK: - Token Finders
    
    private enum CommentStyle { case hash, slashSlash, any }
    
    private static func findComments(in line: String, style: CommentStyle) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        let patterns: [String]
        switch style {
        case .hash: patterns = ["#.*$"]
        case .slashSlash: patterns = ["//.*$"]
        case .any: patterns = ["#.*$", "//.*$"]
        }
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range, in: line) {
                results.append((range, comment))
            }
        }
        
        return results
    }
    
    private static func findStrings(in line: String, includeTripleQuotes: Bool) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        // Pattern for double and single quoted strings (handles escapes)
        let patterns = [
            "\"(?:[^\"\\\\]|\\\\.)*\"",  // Double quoted
            "'(?:[^'\\\\]|\\\\.)*'"       // Single quoted
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
                for match in matches {
                    if let range = Range(match.range, in: line) {
                        results.append((range, string))
                    }
                }
            }
        }
        
        return results
    }
    
    private static func findTemplateStrings(in line: String) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        // Backtick template strings
        let pattern = "`[^`]*`"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
            for match in matches {
                if let range = Range(match.range, in: line) {
                    results.append((range, string))
                }
            }
        }
        
        return results
    }
    
    private static func findDecorators(in line: String, prefix: String) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        let pattern = "\(prefix)\\w+"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
            for match in matches {
                if let range = Range(match.range, in: line) {
                    results.append((range, decorator))
                }
            }
        }
        
        return results
    }
    
    private static func findKeywords(in line: String, keywords: [String]) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        for kw in keywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: kw))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
                for match in matches {
                    if let range = Range(match.range, in: line) {
                        results.append((range, keyword))
                    }
                }
            }
        }
        
        return results
    }
    
    private static func findNumbers(in line: String) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        // Match integers, floats, hex, and negative numbers
        let pattern = "\\b-?(?:0x[0-9a-fA-F]+|\\d+\\.?\\d*(?:[eE][+-]?\\d+)?)\\b"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
            for match in matches {
                if let range = Range(match.range, in: line) {
                    results.append((range, number))
                }
            }
        }
        
        return results
    }
    
    private static func findTypes(in line: String) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        // Capitalized identifiers (likely types/classes)
        let pattern = "\\b[A-Z][a-zA-Z0-9_]*\\b"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
            for match in matches {
                if let range = Range(match.range, in: line) {
                    results.append((range, type))
                }
            }
        }
        
        return results
    }
    
    private static func findFunctionCalls(in line: String) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        // Identifier followed by (
        let pattern = "\\b([a-z_][a-zA-Z0-9_]*)\\s*\\("
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
            for match in matches {
                // Capture group 1 is the function name
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: line) {
                    results.append((range, function))
                }
            }
        }
        
        return results
    }
    
    private static func findJsonKeys(in line: String) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        // Keys are strings followed by :
        let pattern = "\"[^\"]+\"\\s*:"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
            for match in matches {
                if let range = Range(match.range, in: line) {
                    // Exclude the colon from highlighting - find the closing quote
                    if let keyEndClosed = line[range].lastIndex(of: "\"") {
                        let keyStart = range.lowerBound
                        let keyEnd = line.index(after: keyEndClosed)  // Convert to exclusive upper bound
                        if keyStart < keyEnd {
                            let keyRange = keyStart..<keyEnd
                            results.append((keyRange, type))  // Use type color for keys
                        }
                    }
                }
            }
        }
        
        return results
    }
    
    private static func findBashVariables(in line: String) -> [(Range<String.Index>, Color)] {
        var results: [(Range<String.Index>, Color)] = []
        
        // $VAR or ${VAR}
        let patterns = ["\\$\\{?[a-zA-Z_][a-zA-Z0-9_]*\\}?"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
                for match in matches {
                    if let range = Range(match.range, in: line) {
                        results.append((range, type))
                    }
                }
            }
        }
        
        return results
    }
    
    // MARK: - Keyword Lists
    
    private static let pythonKeywords = [
        "def", "class", "import", "from", "return", "if", "elif", "else", "for", "while",
        "try", "except", "finally", "with", "as", "in", "not", "and", "or", "is",
        "None", "True", "False", "self", "lambda", "yield", "async", "await",
        "raise", "pass", "break", "continue", "global", "nonlocal", "assert", "del"
    ]
    
    private static let swiftKeywords = [
        "func", "var", "let", "struct", "class", "enum", "protocol", "extension", "import",
        "return", "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
        "do", "try", "catch", "throw", "throws", "rethrows", "async", "await",
        "self", "Self", "nil", "true", "false", "some", "any", "where",
        "private", "fileprivate", "internal", "public", "open", "static", "final",
        "override", "mutating", "nonmutating", "lazy", "weak", "unowned",
        "init", "deinit", "get", "set", "willSet", "didSet", "inout", "typealias",
        "associatedtype", "subscript", "convenience", "required", "optional", "indirect"
    ]
    
    private static let jsKeywords = [
        "function", "const", "let", "var", "return", "if", "else", "for", "while", "do",
        "switch", "case", "default", "break", "continue", "class", "extends", "super",
        "import", "export", "from", "as", "async", "await", "try", "catch", "finally",
        "throw", "new", "this", "typeof", "instanceof", "delete", "void", "yield",
        "null", "undefined", "true", "false", "NaN", "Infinity",
        "static", "get", "set", "of", "in"
    ]
    
    private static let bashKeywords = [
        "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
        "function", "return", "exit", "break", "continue", "in", "select", "until",
        "echo", "printf", "read", "export", "local", "declare", "readonly", "unset",
        "source", "alias", "cd", "pwd", "ls", "cp", "mv", "rm", "mkdir", "rmdir",
        "cat", "grep", "sed", "awk", "find", "xargs", "test", "true", "false"
    ]
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String
    
    @State private var copied = false
    
    // Dark theme colors
    private let backgroundColor = Color(red: 0.157, green: 0.165, blue: 0.212)  // #282A36
    private let headerColor = Color(red: 0.2, green: 0.208, blue: 0.255)        // Slightly lighter
    private let lineNumberColor = Color(red: 0.55, green: 0.6, blue: 0.7)  // Lighter gray for better contrast
    
    /// Nicely formatted language name for display
    private var displayLanguage: String {
        switch language.lowercased() {
        case "python", "py": return "Python"
        case "swift": return "Swift"
        case "javascript", "js": return "JavaScript"
        case "typescript", "ts": return "TypeScript"
        case "jsx": return "JSX"
        case "tsx": return "TSX"
        case "json": return "JSON"
        case "bash", "sh", "shell", "zsh": return "Bash"
        case "html": return "HTML"
        case "css": return "CSS"
        case "sql": return "SQL"
        case "rust": return "Rust"
        case "go": return "Go"
        case "java": return "Java"
        case "kotlin": return "Kotlin"
        case "ruby", "rb": return "Ruby"
        case "php": return "PHP"
        case "c": return "C"
        case "cpp", "c++": return "C++"
        case "csharp", "c#", "cs": return "C#"
        case "yaml", "yml": return "YAML"
        case "xml": return "XML"
        case "markdown", "md": return "Markdown"
        default: return language.isEmpty ? "Code" : language.capitalized
        }
    }
    
    private var lines: [String] {
        code.components(separatedBy: "\n")
    }
    
    private var lineNumberWidth: CGFloat {
        let maxLineNumber = lines.count
        let digitCount = String(maxLineNumber).count
        return CGFloat(digitCount * 10 + 16)  // ~10pt per digit + padding
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar with language and copy button
            HStack {
                Text(displayLanguage)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.7))
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                        if copied {
                            Text("Copied")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(copied ? .green : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerColor)
            
            // Code area with line numbers
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers (fixed, don't scroll horizontally)
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                            Text("\(index + 1)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(lineNumberColor)
                                .frame(height: 20)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 12)
                    .background(backgroundColor)
                    
                    // Separator line
                    Rectangle()
                        .fill(lineNumberColor.opacity(0.3))
                        .frame(width: 1)
                        .padding(.vertical, 8)
                    
                    // Highlighted code
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(SyntaxHighlighter.highlight(line, language: language))
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 20, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
                }
            }
            .background(backgroundColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif
        
        copied = true
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Weather Card View

struct WeatherCardView: View {
    let data: WeatherData

    /// Condition-aware gradient based on OWM icon code
    /// All gradients are dark enough for white text readability
    private var backgroundGradient: LinearGradient {
        let base = String(data.iconCode.prefix(2))
        let isNight = data.iconCode.hasSuffix("n")

        let colors: [Color]
        switch base {
        case "01":  // Clear
            colors = isNight
                ? [Color(red: 0.08, green: 0.12, blue: 0.28), Color(red: 0.12, green: 0.18, blue: 0.38)]
                : [Color(red: 0.2, green: 0.45, blue: 0.7), Color(red: 0.35, green: 0.55, blue: 0.75)]
        case "02":  // Few clouds
            colors = isNight
                ? [Color(red: 0.12, green: 0.18, blue: 0.35), Color(red: 0.22, green: 0.28, blue: 0.42)]
                : [Color(red: 0.25, green: 0.5, blue: 0.7), Color(red: 0.4, green: 0.55, blue: 0.7)]
        case "03", "04":  // Clouds
            colors = isNight
                ? [Color(red: 0.2, green: 0.22, blue: 0.26), Color(red: 0.15, green: 0.17, blue: 0.2)]
                : [Color(red: 0.4, green: 0.45, blue: 0.52), Color(red: 0.5, green: 0.55, blue: 0.6)]
        case "09", "10":  // Rain
            colors = isNight
                ? [Color(red: 0.15, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.12, blue: 0.18)]
                : [Color(red: 0.3, green: 0.4, blue: 0.52), Color(red: 0.38, green: 0.45, blue: 0.55)]
        case "11":  // Thunderstorm
            colors = isNight
                ? [Color(red: 0.18, green: 0.12, blue: 0.22), Color(red: 0.1, green: 0.08, blue: 0.14)]
                : [Color(red: 0.3, green: 0.25, blue: 0.38), Color(red: 0.22, green: 0.2, blue: 0.3)]
        case "13":  // Snow
            colors = isNight
                ? [Color(red: 0.28, green: 0.35, blue: 0.45), Color(red: 0.2, green: 0.28, blue: 0.38)]
                : [Color(red: 0.4, green: 0.5, blue: 0.62), Color(red: 0.5, green: 0.58, blue: 0.68)]
        case "50":  // Fog/mist
            colors = isNight
                ? [Color(red: 0.25, green: 0.28, blue: 0.32), Color(red: 0.35, green: 0.38, blue: 0.42)]
                : [Color(red: 0.45, green: 0.5, blue: 0.55), Color(red: 0.55, green: 0.58, blue: 0.62)]
        default:
            colors = [Color(red: 0.4, green: 0.45, blue: 0.52), Color(red: 0.5, green: 0.55, blue: 0.6)]
        }

        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// Returns a color for the weather icon based on condition
    private func weatherIconColor(for iconCode: String) -> Color {
        let base = String(iconCode.prefix(2))
        let isNight = iconCode.hasSuffix("n")
        switch base {
        case "01": return isNight ? .white : Color(red: 1.0, green: 0.85, blue: 0.0)  // bright yellow sun, white moon
        case "02": return isNight ? .white : Color(red: 1.0, green: 0.85, blue: 0.0)  // yellow sun with clouds too
        case "03", "04": return .gray    // clouds
        case "09", "10": return .cyan    // rain
        case "11": return .purple        // thunderstorm
        case "13": return .white         // snow
        case "50": return .gray          // fog/mist
        default: return .white
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // City name + observation time
            VStack(alignment: .leading, spacing: 2) {
                Text(data.city)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let obsTime = data.formattedObservationTime {
                    Text("as of \(obsTime)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Main row: icon + temperature
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: data.symbolName)
                    .font(.system(size: 40))
                    .foregroundStyle(weatherIconColor(for: data.iconCode))
                    .symbolRenderingMode(.hierarchical)

                Text("\(Int(round(data.temp)))°")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white)
            }

            // Conditions
            Text(data.conditions)
                .font(.title3)
                .foregroundStyle(.white)

            // High/Low line (if available)
            if let high = data.high, let low = data.low {
                Text("High: \(Int(round(high)))°  Low: \(Int(round(low)))°")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            // Details row
            Text("Feels like \(Int(round(data.feelsLike)))° • Humidity \(data.humidity)% • Wind \(String(format: "%.0f", data.windSpeed)) mph")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

            // Hourly forecast row
            if !data.hourlyForecast.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 1)
                    .padding(.vertical, 4)

                HStack(spacing: 0) {
                    ForEach(Array(data.hourlyForecast.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .center, spacing: 4) {
                            // Hour label
                            Text(entry.hour)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))

                            // Weather icon
                            Image(systemName: entry.symbolName)
                                .font(.system(size: 20))
                                .foregroundStyle(weatherIconColor(for: entry.iconCode))
                                .symbolRenderingMode(.hierarchical)
                                .frame(height: 24)

                            // Precipitation %
                            HStack(spacing: 2) {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 8))
                                Text("\(Int(round(entry.pop * 100)))%")
                            }
                            .font(.caption2)
                            .foregroundStyle(entry.pop > 0 ? .cyan : .white.opacity(0.6))

                            // Temperature
                            Text("\(Int(round(entry.temp)))°F")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
        #if os(macOS)
        .frame(width: 900, height: 600)
        #endif
}

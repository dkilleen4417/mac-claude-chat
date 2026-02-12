//
//  ContentView.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//
//  Phase 2 final: Pure view composition. All state and logic lives in ChatViewModel.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @State private var viewModel = ChatViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            chatView
        }
        .task {
            viewModel.configure(modelContext: modelContext)
            if viewModel.claudeService.hasAPIKey {
                viewModel.initializeDatabase()
            }
        }
        .onChange(of: viewModel.needsAPIKey) { oldValue, newValue in
            if oldValue == true && newValue == false {
                viewModel.initializeDatabase()
            }
        }
        .onChange(of: viewModel.selectedChat) { oldValue, newValue in
            if let chatId = newValue {
                viewModel.loadChat(chatId: chatId)
            }
        }
        .alert("New Chat", isPresented: $viewModel.showingNewChatDialog) {
            TextField("Chat Name", text: $viewModel.newChatName)
            Button("Cancel", role: .cancel) {
                viewModel.newChatName = ""
            }
            Button("Create") {
                viewModel.createNewChat()
            }
            .disabled(viewModel.newChatName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the new chat")
        }
        .alert("Rename Chat", isPresented: Binding(
            get: { viewModel.renamingChatId != nil },
            set: { if !$0 { viewModel.renamingChatId = nil } }
        )) {
            TextField("Chat Name", text: $viewModel.renameChatText)
            Button("Cancel", role: .cancel) {
                viewModel.renamingChatId = nil
                viewModel.renameChatText = ""
            }
            Button("Rename") {
                viewModel.renameCurrentChat()
            }
            .disabled(viewModel.renameChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a new name for the chat")
        }
        .alert("Under Construction", isPresented: $viewModel.showUnderConstruction) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This feature is coming soon.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            viewModel.showingNewChatDialog = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearChat)) { _ in
            viewModel.clearCurrentChat()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteChat)) { _ in
            if let chatId = viewModel.selectedChat,
               let chat = viewModel.chats.first(where: { $0.id == chatId }),
               !chat.isDefault {
                viewModel.deleteChat(chat)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAPIKeySettings)) { _ in
            viewModel.showingAPIKeySetup = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWebToolManager)) { _ in
            viewModel.showingWebToolManager = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .publishChat)) { _ in
            if let chatId = viewModel.selectedChat {
                viewModel.publishChat(chatId: chatId)
            }
        }
        .sheet(isPresented: $viewModel.showingWebToolManager) {
            WebToolManagerView()
        }
        .sheet(isPresented: $viewModel.showingAPIKeySetup) {
            APIKeySetupView(isPresented: $viewModel.showingAPIKeySetup) {
                viewModel.needsAPIKey = false
            }
        }
        .sheet(isPresented: $viewModel.needsAPIKey) {
            APIKeySetupView(isPresented: $viewModel.needsAPIKey) {
                viewModel.needsAPIKey = false
            }
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $viewModel.showingTokenAudit) {
            TokenAuditView(messages: viewModel.messages, model: viewModel.selectedModel)
        }
        .task {
            if !viewModel.claudeService.hasAPIKey {
                viewModel.needsAPIKey = true
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chats")
                    .font(.headline)

                Spacer()

                Button(action: {
                    viewModel.showingNewChatDialog = true
                }) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(viewModel.sortedChats, id: \.id, selection: $viewModel.selectedChat) { chat in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.name)
                        Text(viewModel.friendlyTime(from: chat.lastUpdated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Menu {
                        if !chat.isDefault {
                            Button {
                                viewModel.renamingChatId = chat.id
                                viewModel.renameChatText = chat.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                        }

                        Button {
                            viewModel.showUnderConstruction = true
                        } label: {
                            Label("Star", systemImage: "star")
                        }

                        Button {
                            viewModel.showUnderConstruction = true
                        } label: {
                            Label("Add to Project", systemImage: "folder")
                        }

                        Button {
                            viewModel.publishChat(chatId: chat.id)
                        } label: {
                            Label("Publish…", systemImage: "arrow.up.doc")
                        }

                        if !chat.isDefault {
                            Divider()
                            Button(role: .destructive) {
                                viewModel.deleteChat(chat)
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
                            viewModel.deleteChat(chat)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
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

                if let chatName = viewModel.selectedChat {
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
                        if viewModel.messages.isEmpty {
                            Text("Chat messages will appear here")
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                                let turnGrade: Int = {
                                    if message.role == .user {
                                        return message.textGrade
                                    } else {
                                        if !message.turnId.isEmpty {
                                            if let userMsg = viewModel.messages.first(where: { $0.turnId == message.turnId && $0.role == .user }) {
                                                return userMsg.textGrade
                                            }
                                        }
                                        for i in stride(from: index - 1, through: 0, by: -1) {
                                            if viewModel.messages[i].role == .user {
                                                return viewModel.messages[i].textGrade
                                            }
                                        }
                                        return message.textGrade
                                    }
                                }()

                                MessageBubble(
                                    message: message,
                                    turnGrade: turnGrade,
                                    threshold: viewModel.contextThreshold,
                                    onGradeChange: { newGrade in
                                        viewModel.updateMessageGrade(messageId: message.id, grade: newGrade)
                                    },
                                    onCopyTurn: {
                                        viewModel.copyTurn(for: message)
                                    }
                                )
                                .id(message.id)
                            }

                            if let streamingId = viewModel.streamingMessageId, !viewModel.streamingContent.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("🧠")
                                        .font(.body)

                                    MarkdownMessageView(content: viewModel.streamingContent)

                                    Spacer()
                                }
                                .id(streamingId)
                            }

                            if let toolMessage = viewModel.toolActivityMessage {
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

                            if viewModel.isLoading && viewModel.streamingContent.isEmpty && viewModel.toolActivityMessage == nil {
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
                .onChange(of: viewModel.messages.count) { _, _ in
                    if viewModel.messages.last != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo("bottom-spacer", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    if let streamingId = viewModel.streamingMessageId {
                        withAnimation {
                            proxy.scrollTo(streamingId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isLoading) { _, newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation {
                                proxy.scrollTo("thinking-indicator", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: viewModel.toolActivityMessage) { _, newValue in
                    if newValue != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo("tool-activity-indicator", anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Status bar
            VStack(spacing: 4) {
                HStack {
                    Button {
                        viewModel.showingTokenAudit = true
                    } label: {
                        Text("\(viewModel.totalInputTokens + viewModel.totalOutputTokens) tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View per-turn token audit")

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("$\(viewModel.calculateCost())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        let newValue = (viewModel.contextThreshold + 1) % 6
                        viewModel.contextThreshold = newValue
                        viewModel.updateContextThreshold(newValue)
                    } label: {
                        Text("Context: \(viewModel.contextThreshold)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(viewModel.contextThreshold > 0 ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Tap to cycle threshold (0-5). Turns with grade < \(viewModel.contextThreshold) are excluded from context.")

                    Spacer()

                    Menu {
                        Button("Grade All 5 (Full Context)") {
                            viewModel.confirmBulkGrade(grade: 5)
                        }
                        Button("Grade All 0 (Clear Context)") {
                            viewModel.confirmBulkGrade(grade: 0)
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Bulk grade actions")

                    Button("Clear Chat") {
                        viewModel.clearCurrentChat()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                if viewModel.errorMessage != nil {
                    HStack {
                        Text(viewModel.errorMessage!)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Input area
            VStack(spacing: 8) {
                if !viewModel.pendingImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.pendingImages) { pending in
                                PendingImageThumbnail(
                                    pending: pending,
                                    onRemove: { viewModel.removePendingImage(id: pending.id) }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 70)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    Button {
                        viewModel.showingImagePicker = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("Attach image")

                    ZStack(alignment: .topLeading) {
                        #if os(macOS)
                        SpellCheckingTextEditor(
                            text: $viewModel.messageText,
                            contentHeight: $viewModel.inputHeight,
                            onReturn: { viewModel.sendMessage() },
                            onImagePaste: { imageData in
                                viewModel.addImageFromData(imageData)
                            },
                            onTextFileDrop: { text in
                                viewModel.messageText += text
                            }
                        )
                        .frame(height: min(max(viewModel.inputHeight, 36), 200))
                        #else
                        Text(viewModel.messageText.isEmpty ? " " : viewModel.messageText)
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
                                viewModel.inputHeight = max(36, height)
                            }

                        TextEditor(text: $viewModel.messageText)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(height: min(max(viewModel.inputHeight, 36), 200))
                        #endif

                        if viewModel.messageText.isEmpty && viewModel.pendingImages.isEmpty {
                            Text("Type your message...")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 9)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(PlatformColor.textBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.15), value: viewModel.inputHeight)
                    .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                        viewModel.handleImageDrop(providers: providers)
                        return true
                    }

                    Button("Send") {
                        viewModel.sendMessage()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.pendingImages.isEmpty) || viewModel.isLoading)
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
                isPresented: $viewModel.showingImagePicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                viewModel.handleFileImport(result: result)
            }
        }
    }
}

#Preview {
    ContentView()
        #if os(macOS)
        .frame(width: 900, height: 600)
        #endif
}

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

// MARK: - Image Processing

/// Utility for processing images before sending to Claude API
/// Downscales to 1024px max edge and encodes as JPEG base64
enum ImageProcessor {

    /// Result of processing an image
    struct ProcessedImage {
        let id: UUID
        let base64Data: String
        let mediaType: String  // Always "image/jpeg"
    }

    /// Process platform image data into base64 JPEG
    /// - Parameter imageData: Raw image data (PNG, JPEG, etc.)
    /// - Returns: ProcessedImage with base64 data, or nil if processing fails
    static func process(_ imageData: Data) -> ProcessedImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: imageData) else { return nil }
        return processNSImage(nsImage)
        #else
        guard let uiImage = UIImage(data: imageData) else { return nil }
        return processUIImage(uiImage)
        #endif
    }

    #if os(macOS)
    /// Process NSImage (macOS)
    static func processNSImage(_ image: NSImage) -> ProcessedImage? {
        // Get the actual pixel dimensions from the image rep
        guard let bitmapRep = image.representations.first else { return nil }
        let pixelWidth = CGFloat(bitmapRep.pixelsWide)
        let pixelHeight = CGFloat(bitmapRep.pixelsHigh)

        // Calculate scale to fit within 1024px on the long edge
        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / max(pixelWidth, pixelHeight), 1.0)
        let newWidth = pixelWidth * scale
        let newHeight = pixelHeight * scale

        // Create scaled image
        let newSize = NSSize(width: newWidth, height: newHeight)
        let scaledImage = NSImage(size: newSize)
        scaledImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: NSSize(width: pixelWidth, height: pixelHeight)),
                   operation: .copy,
                   fraction: 1.0)
        scaledImage.unlockFocus()

        // Convert to JPEG data
        guard let tiffData = scaledImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }

        let base64 = jpegData.base64EncodedString()
        return ProcessedImage(id: UUID(), base64Data: base64, mediaType: "image/jpeg")
    }
    #endif

    #if os(iOS)
    /// Process UIImage (iOS)
    static func processUIImage(_ image: UIImage) -> ProcessedImage? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale

        // Calculate scale to fit within 1024px on the long edge
        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / max(pixelWidth, pixelHeight), 1.0)
        let newWidth = pixelWidth * scale
        let newHeight = pixelHeight * scale

        // Create scaled image
        let newSize = CGSize(width: newWidth, height: newHeight)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let scaledImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // Convert to JPEG data
        guard let jpegData = scaledImage.jpegData(compressionQuality: 0.7) else {
            return nil
        }

        let base64 = jpegData.base64EncodedString()
        return ProcessedImage(id: UUID(), base64Data: base64, mediaType: "image/jpeg")
    }
    #endif
}

/// Pending image attachment waiting to be sent
struct PendingImage: Identifiable {
    let id: UUID
    let base64Data: String
    let mediaType: String
    let thumbnailData: Data  // For preview display

    #if os(macOS)
    var thumbnailImage: NSImage? {
        NSImage(data: thumbnailData)
    }
    #else
    var thumbnailImage: UIImage? {
        UIImage(data: thumbnailData)
    }
    #endif
}

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
    var onImagePaste: ((Data) -> Void)?

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

        let textView = PasteInterceptingTextView()
        textView.delegate = context.coordinator
        textView.onImagePaste = { imageData in
            context.coordinator.parent.onImagePaste?(imageData)
        }
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

/// NSTextView subclass that intercepts paste and drag-drop to handle images
class PasteInterceptingTextView: NSTextView {
    var onImagePaste: ((Data) -> Void)?

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Check for image data first
        if let imageData = pasteboard.data(forType: .png) {
            onImagePaste?(imageData)
            return
        }
        if let imageData = pasteboard.data(forType: .tiff) {
            onImagePaste?(imageData)
            return
        }
        // Check for file URLs that might be images
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                   UTType(uti)?.conforms(to: .image) == true,
                   let imageData = try? Data(contentsOf: url) {
                    onImagePaste?(imageData)
                    return
                }
            }
        }

        // Fall through to normal paste for text
        super.paste(sender)
    }

    // MARK: - Drag and Drop Interception

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard

        // Check if this is an image drop we want to handle
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                for url in urls {
                    if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                       let type = UTType(uti),
                       type.conforms(to: .image) {
                        return .copy
                    }
                }
            }
        }

        // Check for direct image data
        if pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil {
            return .copy
        }

        // Fall back to default behavior for text drops
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Try to handle as image file URL first
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                   let type = UTType(uti),
                   type.conforms(to: .image),
                   let imageData = try? Data(contentsOf: url) {
                    onImagePaste?(imageData)
                    return true
                }
            }
        }

        // Try direct image data
        if let imageData = pasteboard.data(forType: .png) {
            onImagePaste?(imageData)
            return true
        }
        if let imageData = pasteboard.data(forType: .tiff) {
            onImagePaste?(imageData)
            return true
        }

        // Fall back to default behavior for text
        return super.performDragOperation(sender)
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
                if !trimmedText.isEmpty {
                    currentMessageContent.append([
                        "type": "text",
                        "text": trimmedText
                    ])
                }

                // Add current message to apiMessages
                if currentMessageContent.isEmpty {
                    // Shouldn't happen due to guard above, but fallback
                    apiMessages.append(["role": "user", "content": trimmedText])
                } else if currentMessageContent.count == 1 && imagesToSend.isEmpty {
                    // Text only - can use simple string format
                    apiMessages.append(["role": "user", "content": trimmedText])
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
                    timestamp: Date(),
                    turnId: turnId,
                    isFinalResponse: true,  // This is the final response for this turn
                    inputTokens: totalStreamInputTokens,
                    outputTokens: totalStreamOutputTokens
                )

                messages.append(assistantMessage)
                streamingMessageId = nil
                streamingContent = ""
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

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    ContentView()
        #if os(macOS)
        .frame(width: 900, height: 600)
        #endif
}

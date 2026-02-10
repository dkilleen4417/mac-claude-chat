//
//  SpellCheckingTextEditor.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 3 decomposition
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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

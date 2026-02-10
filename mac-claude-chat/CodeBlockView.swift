//
//  CodeBlockView.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 1 decomposition
//

import SwiftUI

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

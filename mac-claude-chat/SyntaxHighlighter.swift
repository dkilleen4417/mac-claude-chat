//
//  SyntaxHighlighter.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 1 decomposition
//

import SwiftUI

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

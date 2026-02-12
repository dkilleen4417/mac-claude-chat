//
//  MessageContentParser.swift
//  mac-claude-chat
//
//  Single source of truth for parsing HTML comment markers
//  embedded in message content (images, weather, tips).
//

import Foundation

enum MessageContentParser {

    // MARK: - Parsed Result Types

    struct ParsedContent {
        let displayText: String
        let images: [ImageMarker]
        let weatherData: [WeatherData]
        let tip: String?
        let rawText: String
    }

    struct ImageMarker {
        let id: String
        let mediaType: String
        let base64Data: String
    }

    // MARK: - Full Parse

    /// Parse all marker types from message content.
    /// Returns structured data and cleaned display text.
    static func parse(_ content: String) -> ParsedContent {
        return ParsedContent(
            displayText: stripAllMarkers(content),
            images: extractImages(from: content),
            weatherData: extractWeather(from: content),
            tip: extractTip(from: content),
            rawText: content
        )
    }

    // MARK: - Strip Operations

    /// Strip ALL marker types (image, weather, tip) from content.
    /// Use for: API payloads, clipboard copy, export.
    static func stripAllMarkers(_ content: String) -> String {
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

    /// Strip only image markers. Returns cleaned text.
    /// Use for: MessageBubble display where weather/tip are handled separately.
    static func stripImageMarkers(_ content: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<!--image:\\{.+?\\}-->\\n?", options: []) else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip only weather markers. Returns cleaned text.
    /// Use for: MarkdownMessageView where weather cards are rendered separately.
    static func stripWeatherMarkers(_ content: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<!--weather:.+?-->\\n?", options: []) else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
    }

    // MARK: - Extract Operations

    /// Extract image markers from content.
    /// Returns array of parsed image data.
    static func extractImages(from content: String) -> [ImageMarker] {
        var images: [ImageMarker] = []
        let pattern = "<!--image:(\\{.+?\\})-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return images
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
                    images.append(ImageMarker(id: id, mediaType: mediaType, base64Data: base64Data))
                }
            }
        }
        return images
    }

    /// Extract weather data from content.
    /// Returns array of decoded WeatherData structs.
    static func extractWeather(from content: String) -> [WeatherData] {
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

    /// Extract iceberg tip from content.
    /// Returns the tip text (without marker wrapper), or nil if not found.
    static func extractTip(from content: String) -> String? {
        let pattern = "<!--tip:(.+?)-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let tipRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        return String(content[tipRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip tip marker from content and return both cleaned text and extracted tip.
    /// Use for: Processing streaming response after completion.
    static func extractAndStripTip(from content: String) -> (cleanedContent: String, tip: String?) {
        let tip = extractTip(from: content)

        guard let regex = try? NSRegularExpression(pattern: "<!--tip:.+?-->\\n?", options: [.dotMatchesLineSeparators]) else {
            return (content, tip)
        }

        let range = NSRange(content.startIndex..., in: content)
        let cleaned = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleaned, tip)
    }

    /// Extract images and return both the image data and the cleaned text (images stripped).
    /// Use for: Building API messages from stored content.
    static func extractImagesAndCleanText(from content: String) -> (images: [ImageMarker], cleanText: String) {
        let images = extractImages(from: content)
        let cleanText = stripImageMarkers(content)
        return (images, cleanText)
    }
}

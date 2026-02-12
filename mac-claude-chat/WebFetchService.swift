//
//  WebFetchService.swift
//  mac-claude-chat
//
//  Web Tools: generic HTTP fetch with HTML-to-text extraction.
//  Handles the fetch-and-clean step of the web_lookup tool.
//  No external dependencies — Foundation only.
//

import Foundation

/// Result of a web fetch operation
enum WebFetchResult {
    case success(content: String, url: String)
    case failure(reason: String, url: String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// The text content on success, or the error reason on failure
    var text: String {
        switch self {
        case .success(let content, _): return content
        case .failure(let reason, _): return reason
        }
    }
}

/// Stateless service for fetching web pages and extracting readable text.
/// Uses enum namespace pattern consistent with ToolService.
enum WebFetchService {

    /// Default timeout for HTTP requests (seconds)
    private static let requestTimeout: TimeInterval = 10

    /// Maximum characters to return after HTML stripping.
    /// Controls token cost when content is sent to the LLM.
    private static let maxContentLength = 4000

    /// Minimum content length to consider a fetch "usable."
    /// Below this threshold, content is treated as a failed fetch.
    private static let minContentLength = 50

    // MARK: - Public API

    /// Fetch a URL and return cleaned text content.
    ///
    /// - Parameters:
    ///   - urlString: The fully resolved URL to fetch.
    ///   - extractionHint: Optional hint about what content to prioritize (for logging).
    /// - Returns: A `WebFetchResult` with cleaned text or an error reason.
    static func fetch(url urlString: String, extractionHint: String = "") async -> WebFetchResult {
        guard let url = URL(string: urlString) else {
            return .failure(reason: "Invalid URL: \(urlString)", url: urlString)
        }

        print("🌐 WebFetch: \(urlString)")

        do {
            var request = URLRequest(url: url, timeoutInterval: requestTimeout)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("text/html,application/xhtml+xml,text/plain", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(reason: "Non-HTTP response", url: urlString)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(
                    reason: "HTTP \(httpResponse.statusCode)",
                    url: urlString
                )
            }

            guard let rawHTML = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .ascii) else {
                return .failure(reason: "Unable to decode response body", url: urlString)
            }

            let cleaned = stripHTML(rawHTML)

            guard cleaned.count >= minContentLength else {
                return .failure(
                    reason: "Content too short (\(cleaned.count) chars) — likely blocked or empty page",
                    url: urlString
                )
            }

            let truncated = String(cleaned.prefix(maxContentLength))
            print("🌐 WebFetch: got \(truncated.count) chars from \(url.host ?? "unknown")")

            return .success(content: truncated, url: urlString)

        } catch let error as URLError where error.code == .timedOut {
            return .failure(reason: "Request timed out after \(Int(requestTimeout))s", url: urlString)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            return .failure(reason: "No internet connection", url: urlString)
        } catch {
            return .failure(reason: "Fetch error: \(error.localizedDescription)", url: urlString)
        }
    }

    /// Resolve a URL pattern by substituting `{placeholder}` tokens with values.
    ///
    /// - Parameters:
    ///   - pattern: URL string with `{key}` placeholders (e.g., `https://example.com?lat={lat}&lon={lon}`)
    ///   - parameters: Dictionary of key-value pairs for substitution.
    /// - Returns: The resolved URL string, or nil if a required placeholder has no value.
    static func resolveURL(pattern: String, parameters: [String: String]) -> String? {
        var resolved = pattern

        // Find all {placeholder} tokens in the pattern
        let regex = try? NSRegularExpression(pattern: "\\{(\\w+)\\}")
        let matches = regex?.matches(in: pattern, range: NSRange(pattern.startIndex..., in: pattern)) ?? []

        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: pattern) else { continue }
            let key = String(pattern[keyRange])
            guard let value = parameters[key], !value.isEmpty else {
                // Missing parameter — cannot resolve
                print("🌐 WebFetch: missing parameter '{\(key)}' in URL pattern")
                return nil
            }
            // URL-encode the value for safe substitution
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            resolved = resolved.replacingOccurrences(of: "{\(key)}", with: encoded)
        }

        return resolved
    }

    /// Attempt to fetch from a prioritized list of sources with fallback.
    ///
    /// - Parameters:
    ///   - sources: Array of (urlPattern, extractionHint) tuples, in priority order.
    ///   - parameters: Placeholder values for URL resolution.
    /// - Returns: The first successful `WebFetchResult`, or the last failure.
    static func fetchWithFallback(
        sources: [(urlPattern: String, extractionHint: String)],
        parameters: [String: String]
    ) async -> WebFetchResult {
        var lastFailure: WebFetchResult = .failure(reason: "No sources configured", url: "")

        for (pattern, hint) in sources {
            guard let resolvedURL = resolveURL(pattern: pattern, parameters: parameters) else {
                lastFailure = .failure(reason: "Could not resolve URL pattern: \(pattern)", url: pattern)
                continue
            }

            let result = await fetch(url: resolvedURL, extractionHint: hint)

            if result.isSuccess {
                return result
            }

            // Log and try next source
            print("🌐 WebFetch: source failed (\(result.text)), trying next...")
            lastFailure = result
        }

        return lastFailure
    }

    // MARK: - HTML Stripping

    /// Strip HTML tags, scripts, styles, and navigation from raw HTML.
    /// Returns readable plain text suitable for LLM consumption.
    private static func stripHTML(_ html: String) -> String {
        var text = html

        // Remove script and style blocks entirely (including content)
        let blockPatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<header[^>]*>[\\s\\S]*?</header>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<noscript[^>]*>[\\s\\S]*?</noscript>"
        ]
        for pattern in blockPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " "
                )
            }
        }

        // Replace <br>, <p>, <div>, <li>, <tr> with newlines for readability
        let newlinePatterns = ["<br[^>]*/?>", "</p>", "</div>", "</li>", "</tr>", "</h[1-6]>"]
        for pattern in newlinePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: "\n"
                )
            }
        }

        // Strip all remaining HTML tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) {
            text = tagRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }

        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&deg;", with: "°")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")

        // Collapse excessive whitespace
        // Multiple spaces → single space
        if let spaceRegex = try? NSRegularExpression(pattern: "[ \\t]+") {
            text = spaceRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        // Multiple newlines → double newline (paragraph break)
        if let nlRegex = try? NSRegularExpression(pattern: "\\n{3,}") {
            text = nlRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\n\n"
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

//
//  ToolService.swift
//  mac-claude-chat
//
//  Created by Drew on 2/6/26.
//

import Foundation

/// Tool call parsed from Claude's streaming response
struct ToolCall {
    let id: String
    let name: String
    let input: [String: Any]
}

/// Hourly forecast entry for card rendering
struct HourlyForecast: Codable {
    let hour: String        // e.g., "Now", "10 PM", "11 PM"
    let temp: Double
    let conditions: String
    let iconCode: String    // OWM icon code (e.g., "02n", "01d")
    let pop: Double         // probability of precipitation (0.0–1.0)

    /// SF Symbol name derived from OWM icon code
    var symbolName: String {
        Self.sfSymbol(for: iconCode)
    }

    /// Map OWM icon codes to SF Symbols with day/night variants
    static func sfSymbol(for iconCode: String) -> String {
        let base = String(iconCode.prefix(2))
        let isNight = iconCode.hasSuffix("n")

        switch base {
        case "01": return isNight ? "moon.fill" : "sun.max.fill"
        case "02": return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case "03": return "cloud.fill"
        case "04": return "smoke.fill"
        case "09": return "cloud.drizzle.fill"
        case "10": return isNight ? "cloud.moon.rain.fill" : "cloud.rain.fill"
        case "11": return "cloud.bolt.rain.fill"
        case "13": return "cloud.snow.fill"
        case "50": return "cloud.fog.fill"
        default:   return "cloud.fill"
        }
    }
}

/// Structured weather data for card rendering
struct WeatherData: Codable {
    let city: String
    let temp: Double
    let feelsLike: Double
    let conditions: String
    let humidity: Int
    let windSpeed: Double
    let iconCode: String            // OWM icon code for current conditions
    let high: Double?               // daily high from daily[0]
    let low: Double?                // daily low from daily[0]
    let hourlyForecast: [HourlyForecast]  // next 6 hours
    let observationTime: Int?       // Unix timestamp from current.dt
    let timezoneOffset: Int?        // UTC offset in seconds from API response

    /// SF Symbol name for current conditions
    var symbolName: String {
        HourlyForecast.sfSymbol(for: iconCode)
    }

    /// Formatted observation time in the location's local timezone
    var formattedObservationTime: String? {
        guard let obsTime = observationTime, let offset = timezoneOffset else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(obsTime))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(secondsFromGMT: offset)
        return formatter.string(from: date)
    }
}

/// Tool execution result — plain text for the LLM, optional structured data for the UI
/// Tool execution result — plain text for the LLM, optional structured data for the UI.
/// `overheadInput` / `overheadOutput` track tokens from sub-agent calls (e.g., Haiku extraction).
enum ToolResult {
    case plain(String)
    case weather(text: String, data: WeatherData, overheadInput: Int, overheadOutput: Int)

    /// The string sent back to Claude as tool_result content
    var textForLLM: String {
        switch self {
        case .plain(let text): return text
        case .weather(let text, _, _, _): return text
        }
    }

    /// Overhead tokens consumed by sub-agent calls (e.g., Haiku extraction)
    var overheadTokens: (input: Int, output: Int) {
        switch self {
        case .plain: return (0, 0)
        case .weather(_, _, let input, let output): return (input, output)
        }
    }

    /// JSON marker to embed in the saved message, if any
    var embeddedMarker: String? {
        switch self {
        case .plain: return nil
        case .weather(_, let data, _, _):
            guard let json = try? JSONEncoder().encode(data),
                  let jsonString = String(data: json, encoding: .utf8)
            else { return nil }
            return "<!--weather:\(jsonString)-->"
        }
    }
}

/// Result of a streaming API call, including any tool calls
struct StreamResult {
    let textContent: String
    let toolCalls: [ToolCall]
    let stopReason: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
}

/// Service for defining, dispatching, and executing Claude API tools
enum ToolService {

    // MARK: - Tool Definitions (JSON Schema for Claude API)

    /// Tool definitions array sent with every API request.
    /// Only includes tools whose API keys are available.
    static var toolDefinitions: [[String: Any]] {
        var tools: [[String: Any]] = [
            [
                "name": "get_datetime",
                "description": "Get the current date and time in the user's timezone (Eastern). Use this when you need to know what day or time it is.",
                "input_schema": [
                    "type": "object",
                    "properties": [String: Any](),
                    "required": [String]()
                ]
            ],

            // Web Tools: generic web lookup with source fallback chain
            [
                "name": "web_lookup",
                "description": "Look up current information from trusted web sources. Use this for topics where a web source can provide current, reliable information. Specify the category to use a curated source, or use category 'search' for general web search.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "category": [
                            "type": "string",
                            "description": "The web tool category (e.g., 'weather', 'news', 'finance'). Use 'search' for general web search when no specific category fits."
                        ] as [String: Any],
                        "query": [
                            "type": "string",
                            "description": "The user's question or search terms."
                        ] as [String: Any],
                        "parameters": [
                            "type": "object",
                            "description": "Key-value pairs to fill URL placeholders (e.g., {\"lat\": \"39.27\", \"lon\": \"-76.73\", \"city\": \"Catonsville\"}).",
                            "additionalProperties": ["type": "string"]
                        ] as [String: Any]
                    ],
                    "required": ["category", "query"]
                ] as [String: Any]
            ]
        ]

        if KeychainService.getTavilyKey() != nil {
            tools.append([
                "name": "search_web",
                "description": "Search the web for current information on any topic. Use this when you need up-to-date information about news, sports, current events, weather forecasts, or any topic that changes frequently. Don't deflect with 'I don't have real-time data' — use this tool.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The search query. Be specific and include relevant context."
                        ] as [String: Any]
                    ],
                    "required": ["query"]
                ] as [String: Any]
            ])
        }

        if KeychainService.getTavilyKey() != nil {
            tools.append([
                "name": "get_weather",
                "description": "Get current weather information for a specific location. Defaults to Catonsville, Maryland if no location specified.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "location": [
                            "type": "string",
                            "description": "The location to get weather for (city, state, country). Leave empty for default location."
                        ] as [String: Any]
                    ],
                    "required": ["location"]
                ] as [String: Any]
            ])
        }

        return tools
    }

    // MARK: - Tool Dispatch

    /// Execute a tool by name with the given input parameters.
    /// Returns a ToolResult with text for Claude and optional structured data for the UI.
    static func executeTool(name: String, input: [String: Any]) async -> ToolResult {
        switch name {
        case "get_datetime":
            return .plain(getDatetime())
        case "search_web":
            let query = input["query"] as? String ?? ""
            return .plain(await searchWeb(query: query))
        case "get_weather":
            return .plain("Weather tool requires claudeService — should be routed through executeWeather().")
        default:
            return .plain("Unknown tool: \(name)")
        }
    }

    // MARK: - Tool Implementations

    /// Get current date and time in Eastern timezone
    private static func getDatetime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy h:mm a"
        formatter.timeZone = TimeZone(identifier: "America/New_York")

        let timeZoneAbbr = formatter.timeZone.isDaylightSavingTime(for: Date()) ? "EDT" : "EST"
        let dateString = formatter.string(from: Date())

        return "Current date and time: \(dateString) (\(timeZoneAbbr))"
    }

    /// Search the web using Tavily API
    private static func searchWeb(query: String) async -> String {
        guard let apiKey = KeychainService.getTavilyKey() else {
            return "Web search not available — Tavily API key not configured."
        }

        guard !query.isEmpty else {
            return "No search query provided."
        }

        print("🔍 Searching for: \(query)")

        do {
            let url = URL(string: "https://api.tavily.com/search")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "api_key": apiKey,
                "query": query,
                "search_depth": "advanced",
                "include_answer": true,
                "max_results": 6
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                return "Search failed with HTTP \(statusCode)"
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "Failed to parse search results."
            }

            var results: [String] = []

            // Add AI summary if available
            if let answer = json["answer"] as? String, !answer.isEmpty {
                results.append("[Summary] \(answer)\n")
            }

            // Add search results
            if let searchResults = json["results"] as? [[String: Any]] {
                for (i, result) in searchResults.prefix(6).enumerated() {
                    let title = result["title"] as? String ?? "No title"
                    let url = result["url"] as? String ?? "No URL"
                    let content = result["content"] as? String ?? "No content"
                    results.append("[\(i + 1)] \(title)\nURL: \(url)\n\(content)\n")
                }
            }

            return results.isEmpty ? "No search results found." : results.joined(separator: "\n")

        } catch {
            return "Search error: \(error.localizedDescription)"
        }
    }

    // MARK: - Web Lookup Tool

    /// Execute a web_lookup tool call using the fallback chain from SwiftData.
    /// Called from ContentView with the dataService, since ToolService is stateless.
    ///
    /// - Parameters:
    ///   - input: The tool call input dictionary from Claude.
    ///   - dataService: SwiftDataService instance for querying web tool sources.
    /// - Returns: A ToolResult with the fetched content or an error message.
    static func executeWebLookup(input: [String: Any], dataService: SwiftDataService) async -> ToolResult {
        let category = input["category"] as? String ?? "search"
        let query = input["query"] as? String ?? ""
        let parameters = input["parameters"] as? [String: String] ?? [:]

        print("🌐 web_lookup: category=\(category), query=\(query)")

        // If category is "search", fall through to general web search
        if category == "search" {
            return .plain(await searchWebFallback(query: query))
        }

        // Look up sources for this category
        do {
            let sources = try dataService.loadEnabledSources(forCategoryKeyword: category)

            if sources.isEmpty {
                print("🌐 web_lookup: no sources for category '\(category)', falling back to web search")
                return .plain(await searchWebFallback(query: query))
            }

            // Build source tuples for the fallback chain
            let sourceTuples = sources.map { source in
                (urlPattern: source.urlPattern, extractionHint: source.extractionHint)
            }

            // Execute the fallback chain
            let result = await WebFetchService.fetchWithFallback(
                sources: sourceTuples,
                parameters: parameters
            )

            switch result {
            case .success(let content, let url):
                return .plain("Source: \(url)\n\n\(content)")
            case .failure(let reason, _):
                // All sources failed — fall back to general web search
                print("🌐 web_lookup: all sources failed (\(reason)), falling back to web search")
                return .plain(await searchWebFallback(query: query))
            }
        } catch {
            print("🌐 web_lookup: data error: \(error)")
            return .plain(await searchWebFallback(query: query))
        }
    }

    /// Fallback web search when no curated sources are available or all fail.
    /// Uses Tavily if available, otherwise returns an informative message.
    private static func searchWebFallback(query: String) async -> String {
        // Try Tavily first if API key is available
        if KeychainService.getTavilyKey() != nil {
            return await searchWeb(query: query)
        }

        // No search API available — return a helpful message
        return "No curated web sources matched this query and no web search API key is configured. " +
               "You can add a Tavily API key in Settings for general web search fallback, " +
               "or configure a web tool source for this category in the Web Tools manager."
    }

    // MARK: - Weather Tool (Tavily + Haiku Extraction)

    /// Execute a get_weather tool call using Tavily search + Haiku JSON extraction.
    /// Produces structured WeatherData for the weather card UI.
    ///
    /// - Parameters:
    ///   - input: The tool call input dictionary from Claude.
    ///   - claudeService: ClaudeService instance for the Haiku extraction call.
    /// - Returns: A ToolResult with weather text and structured card data.
    static func executeWeather(input: [String: Any], claudeService: ClaudeService) async -> ToolResult {
        let location = input["location"] as? String ?? ""
        let resolvedLocation = location.isEmpty
            || location.lowercased() == "none"
            || location.lowercased() == "null"
            ? "Catonsville, Maryland"
            : location

        print("🌤️ Getting weather for: \(resolvedLocation)")

        // Step 1: Fetch weather text from Tavily (include hourly forecast)
        let weatherQuery = "current weather and hourly forecast next 6 hours \(resolvedLocation) temperature humidity wind"
        let searchText = await searchWeb(query: weatherQuery)

        guard !searchText.contains("not available") && !searchText.contains("No search results") else {
            return .plain(searchText)
        }

        // Step 2: Extract structured data via Haiku (current + hourly)
        let extractionPrompt = """
        Extract weather data from this text into JSON. Return ONLY valid JSON — no markdown backticks, no explanation, no extra text.

        Required format:
        {
          "city": "city name",
          "temp": current temperature in Fahrenheit as number,
          "feelsLike": feels-like temperature in Fahrenheit as number (use temp if not mentioned),
          "conditions": "brief description like Clear, Partly Cloudy, Light Rain",
          "humidity": humidity percentage as integer (0 if not mentioned),
          "windSpeed": wind speed in mph as number (0 if not mentioned),
          "iconCode": "weather icon code from list below",
          "high": daily high in Fahrenheit as number or null if not mentioned,
          "low": daily low in Fahrenheit as number or null if not mentioned,
          "utcOffsetHours": UTC offset for this location as number (e.g., -5 for EST, -8 for PST, 0 for London, 1 for Paris),
          "hourly": [
            {
              "hour": "display label like 'Now', '3 PM', '4 PM'",
              "temp": temperature in Fahrenheit as number,
              "conditions": "brief description",
              "iconCode": "icon code from list below",
              "pop": precipitation probability 0.0 to 1.0 (0 if not mentioned)
            }
          ]
        }

        For the "hourly" array: include up to 6 entries if hourly forecast data
        is present in the text. The first entry should use "Now" as the hour label.
        If no hourly data is available, return an empty array: "hourly": [].

        For iconCode (both current and hourly), pick the best match:
        "01d" = clear sky day, "01n" = clear sky night,
        "02d" = few clouds day, "02n" = few clouds night,
        "03d" = scattered clouds, "04d" = overcast,
        "09d" = drizzle/showers, "10d" = rain day, "10n" = rain night,
        "11d" = thunderstorm, "13d" = snow, "50d" = fog/mist/haze.
        Use "d" suffix for daytime (6am-8pm), "n" for nighttime.

        Text to extract from:
        \(searchText)
        """

        do {
            let (jsonText, extractionInputTokens, extractionOutputTokens) = try await claudeService.singleShot(
                messages: [["role": "user", "content": extractionPrompt]],
                model: .fast,
                systemPrompt: "You extract structured data from text. Return only valid JSON.",
                maxTokens: 1024
            )

            // Step 3: Strip markdown fences and parse JSON into WeatherData
            var cleanedJson = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedJson.hasPrefix("```") {
                // Remove opening fence (```json or ```)
                if let firstNewline = cleanedJson.firstIndex(of: "\n") {
                    cleanedJson = String(cleanedJson[cleanedJson.index(after: firstNewline)...])
                }
                // Remove closing fence
                if cleanedJson.hasSuffix("```") {
                    cleanedJson = String(cleanedJson.dropLast(3))
                }
                cleanedJson = cleanedJson.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let jsonData = cleanedJson.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                print("🌤️ Haiku returned non-JSON: \(cleanedJson)")
                return .plain(searchText)
            }

            let city = json["city"] as? String ?? resolvedLocation
            let temp = (json["temp"] as? Double) ?? (json["temp"] as? Int).map(Double.init) ?? 0
            let feelsLike = (json["feelsLike"] as? Double) ?? (json["feelsLike"] as? Int).map(Double.init) ?? temp
            let conditions = json["conditions"] as? String ?? "Unknown"
            let humidity = (json["humidity"] as? Int) ?? (json["humidity"] as? Double).map(Int.init) ?? 0
            let windSpeed = (json["windSpeed"] as? Double) ?? (json["windSpeed"] as? Int).map(Double.init) ?? 0
            let iconCode = json["iconCode"] as? String ?? "03d"
            let high = (json["high"] as? Double) ?? (json["high"] as? Int).map(Double.init)
            let low = (json["low"] as? Double) ?? (json["low"] as? Int).map(Double.init)

            // Parse hourly forecast entries (may be empty if Tavily didn't return hourly data)
            var hourlyForecasts: [HourlyForecast] = []
            if let hourlyArray = json["hourly"] as? [[String: Any]] {
                for entry in hourlyArray.prefix(6) {
                    let hour = entry["hour"] as? String ?? ""
                    let hourTemp = (entry["temp"] as? Double) ?? (entry["temp"] as? Int).map(Double.init) ?? 0
                    let hourConditions = entry["conditions"] as? String ?? "Unknown"
                    let hourIcon = entry["iconCode"] as? String ?? "03d"
                    let hourPop = (entry["pop"] as? Double) ?? (entry["pop"] as? Int).map(Double.init) ?? 0

                    guard !hour.isEmpty else { continue }
                    hourlyForecasts.append(HourlyForecast(
                        hour: hour,
                        temp: hourTemp,
                        conditions: hourConditions,
                        iconCode: hourIcon,
                        pop: hourPop
                    ))
                }
            }

            let weatherData = WeatherData(
                city: city,
                temp: temp,
                feelsLike: feelsLike,
                conditions: conditions,
                humidity: humidity,
                windSpeed: windSpeed,
                iconCode: iconCode,
                high: high,
                low: low,
                hourlyForecast: hourlyForecasts,
                observationTime: Int(Date().timeIntervalSince1970),
                timezoneOffset: {
                    if let offsetHours = (json["utcOffsetHours"] as? Double) ?? (json["utcOffsetHours"] as? Int).map(Double.init) {
                        return Int(offsetHours * 3600)
                    }
                    return nil
                }()
            )

            // Build plain text for Claude
            var textLines = [
                "Current Weather for \(city):",
                "• Conditions: \(conditions)",
                "• Temperature: \(String(format: "%.1f", temp))°F (feels like \(String(format: "%.1f", feelsLike))°F)"
            ]
            if let high = high, let low = low {
                textLines.append("• High: \(String(format: "%.0f", high))°F / Low: \(String(format: "%.0f", low))°F")
            }
            textLines.append("• Humidity: \(humidity)%")
            textLines.append("• Wind Speed: \(String(format: "%.1f", windSpeed)) mph")

            return .weather(
                text: textLines.joined(separator: "\n"),
                data: weatherData,
                overheadInput: extractionInputTokens,
                overheadOutput: extractionOutputTokens
            )

        } catch {
            print("🌤️ Haiku extraction failed: \(error), returning plain text")
            return .plain(searchText)
        }
    }
}

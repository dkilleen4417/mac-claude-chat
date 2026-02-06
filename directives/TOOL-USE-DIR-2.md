# DIR-2: Create ToolService.swift

## Objective
Create a new `ToolService.swift` file containing tool definitions (JSON Schema), a tool dispatch function, and implementations for Tavily web search, OpenWeatherMap weather, and datetime. This file is self-contained and not yet called by anything — app compiles with no behavioral change.

## Prerequisites
- DIR-1 completed (KeychainService has `getTavilyKey()` and `getOWMKey()` methods)

## Instructions

### Step 1: Create ToolService.swift
**File**: `mac-claude-chat/ToolService.swift`
**Action**: Create new file

Add this file to the Xcode project in the `mac-claude-chat` group (same level as `ContentView.swift`).

```swift
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

/// Result of a streaming API call, including any tool calls
struct StreamResult {
    let textContent: String
    let toolCalls: [ToolCall]
    let stopReason: String
    let inputTokens: Int
    let outputTokens: Int
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

        if KeychainService.getOWMKey() != nil {
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
    /// Returns the tool result as a string (never throws — errors become result strings).
    static func executeTool(name: String, input: [String: Any]) async -> String {
        switch name {
        case "get_datetime":
            return getDatetime()
        case "search_web":
            let query = input["query"] as? String ?? ""
            return await searchWeb(query: query)
        case "get_weather":
            let location = input["location"] as? String ?? ""
            return await getWeather(location: location)
        default:
            return "Unknown tool: \(name)"
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

    /// Get current weather from OpenWeatherMap
    private static func getWeather(location: String) async -> String {
        guard let apiKey = KeychainService.getOWMKey() else {
            return "Weather not available — OpenWeatherMap API key not configured."
        }

        // Default to Catonsville if empty
        let resolvedLocation = location.isEmpty
            || location.lowercased() == "none"
            || location.lowercased() == "null"
            ? "Catonsville, Maryland"
            : location

        print("🌤️ Getting weather for: \(resolvedLocation)")

        do {
            // Step 1: Geocode the location
            var geoComponents = URLComponents(string: "https://api.openweathermap.org/geo/1.0/direct")!
            geoComponents.queryItems = [
                URLQueryItem(name: "q", value: resolvedLocation),
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "appid", value: apiKey)
            ]

            let (geoData, geoResponse) = try await URLSession.shared.data(from: geoComponents.url!)

            guard let geoHttp = geoResponse as? HTTPURLResponse,
                  (200...299).contains(geoHttp.statusCode) else {
                return "Geocoding failed for '\(resolvedLocation)'."
            }

            guard let geoArray = try JSONSerialization.jsonObject(with: geoData) as? [[String: Any]],
                  let firstResult = geoArray.first,
                  let lat = firstResult["lat"] as? Double,
                  let lon = firstResult["lon"] as? Double else {
                return "Location '\(resolvedLocation)' not found."
            }

            let cityName = firstResult["name"] as? String ?? resolvedLocation

            // Step 2: Get weather data
            var weatherComponents = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
            weatherComponents.queryItems = [
                URLQueryItem(name: "lat", value: String(lat)),
                URLQueryItem(name: "lon", value: String(lon)),
                URLQueryItem(name: "appid", value: apiKey),
                URLQueryItem(name: "units", value: "imperial")
            ]

            let (weatherData, weatherResponse) = try await URLSession.shared.data(from: weatherComponents.url!)

            guard let weatherHttp = weatherResponse as? HTTPURLResponse,
                  (200...299).contains(weatherHttp.statusCode) else {
                return "Weather request failed."
            }

            guard let weatherJson = try JSONSerialization.jsonObject(with: weatherData) as? [String: Any] else {
                return "Failed to parse weather data."
            }

            // Extract weather fields
            let weather = (weatherJson["weather"] as? [[String: Any]])?.first
            let description = (weather?["description"] as? String ?? "Unknown").capitalized
            let main = weatherJson["main"] as? [String: Any] ?? [:]
            let temp = main["temp"] as? Double ?? 0
            let feelsLike = main["feels_like"] as? Double ?? 0
            let humidity = main["humidity"] as? Int ?? 0
            let wind = weatherJson["wind"] as? [String: Any] ?? [:]
            let windSpeed = wind["speed"] as? Double ?? 0

            return """
                Current Weather for \(cityName):
                • Conditions: \(description)
                • Temperature: \(String(format: "%.1f", temp))°F (feels like \(String(format: "%.1f", feelsLike))°F)
                • Humidity: \(humidity)%
                • Wind Speed: \(String(format: "%.1f", windSpeed)) mph
                """

        } catch {
            return "Weather error: \(error.localizedDescription)"
        }
    }
}
```

## Verification
1. Build the app — should compile with zero errors
2. No behavioral changes — the file exists but nothing calls it yet
3. Confirm ToolService.swift appears in the Xcode project navigator

## Checkpoint
- [ ] App compiles without errors
- [ ] ToolService.swift is in the project
- [ ] Existing chat functionality unchanged

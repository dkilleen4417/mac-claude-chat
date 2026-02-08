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
enum ToolResult {
    case plain(String)
    case weather(text: String, data: WeatherData)

    /// The string sent back to Claude as tool_result content
    var textForLLM: String {
        switch self {
        case .plain(let text): return text
        case .weather(let text, _): return text
        }
    }

    /// JSON marker to embed in the saved message, if any
    var embeddedMarker: String? {
        switch self {
        case .plain: return nil
        case .weather(_, let data):
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
    /// Returns a ToolResult with text for Claude and optional structured data for the UI.
    static func executeTool(name: String, input: [String: Any]) async -> ToolResult {
        switch name {
        case "get_datetime":
            return .plain(getDatetime())
        case "search_web":
            let query = input["query"] as? String ?? ""
            return .plain(await searchWeb(query: query))
        case "get_weather":
            let location = input["location"] as? String ?? ""
            return await getWeather(location: location)
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

    /// Get current weather from OpenWeatherMap One Call API 3.0
    private static func getWeather(location: String) async -> ToolResult {
        guard let apiKey = KeychainService.getOWMKey() else {
            return .plain("Weather not available — OpenWeatherMap API key not configured.")
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
                return .plain("Geocoding failed for '\(resolvedLocation)'.")
            }

            guard let geoArray = try JSONSerialization.jsonObject(with: geoData) as? [[String: Any]],
                  let firstResult = geoArray.first,
                  let lat = firstResult["lat"] as? Double,
                  let lon = firstResult["lon"] as? Double else {
                return .plain("Location '\(resolvedLocation)' not found.")
            }

            let cityName = firstResult["name"] as? String ?? resolvedLocation

            // Step 2: Get weather data via One Call API 3.0
            var weatherComponents = URLComponents(string: "https://api.openweathermap.org/data/3.0/onecall")!
            weatherComponents.queryItems = [
                URLQueryItem(name: "lat", value: String(lat)),
                URLQueryItem(name: "lon", value: String(lon)),
                URLQueryItem(name: "appid", value: apiKey),
                URLQueryItem(name: "units", value: "imperial"),
                URLQueryItem(name: "exclude", value: "minutely")
            ]

            let (weatherData, weatherResponse) = try await URLSession.shared.data(from: weatherComponents.url!)

            guard let weatherHttp = weatherResponse as? HTTPURLResponse,
                  (200...299).contains(weatherHttp.statusCode) else {
                let statusCode = (weatherResponse as? HTTPURLResponse)?.statusCode ?? 0
                return .plain("Weather request failed with HTTP \(statusCode).")
            }

            guard let weatherJson = try JSONSerialization.jsonObject(with: weatherData) as? [String: Any] else {
                return .plain("Failed to parse weather data.")
            }

            // Extract timezone offset from top-level response
            let timezoneOffset = weatherJson["timezone_offset"] as? Int

            // Extract current conditions from "current" object
            let current = weatherJson["current"] as? [String: Any] ?? [:]
            let observationTime = current["dt"] as? Int
            let currentWeather = (current["weather"] as? [[String: Any]])?.first
            let description = (currentWeather?["description"] as? String ?? "Unknown").capitalized
            let currentIconCode = currentWeather?["icon"] as? String ?? "03d"
            let temp = current["temp"] as? Double ?? 0
            let feelsLike = current["feels_like"] as? Double ?? 0
            let humidity = current["humidity"] as? Int ?? 0
            let windSpeed = current["wind_speed"] as? Double ?? 0

            // Extract daily high/low from daily[0]
            let dailyArray = weatherJson["daily"] as? [[String: Any]] ?? []
            var high: Double?
            var low: Double?
            if let today = dailyArray.first,
               let dailyTemp = today["temp"] as? [String: Any] {
                high = dailyTemp["max"] as? Double
                low = dailyTemp["min"] as? Double
            }

            // Extract next 6 hours from hourly array
            let hourlyArray = weatherJson["hourly"] as? [[String: Any]] ?? []
            let hourFormatter = DateFormatter()
            hourFormatter.dateFormat = "h a"
            // Use the location's timezone for hour labels
            if let offset = timezoneOffset {
                hourFormatter.timeZone = TimeZone(secondsFromGMT: offset)
            } else {
                hourFormatter.timeZone = TimeZone(identifier: "America/New_York")
            }

            var hourlyForecasts: [HourlyForecast] = []
            for (index, entry) in hourlyArray.prefix(6).enumerated() {
                let dt = entry["dt"] as? Int ?? 0
                let hourDate = Date(timeIntervalSince1970: TimeInterval(dt))
                let hourLabel = index == 0 ? "Now" : hourFormatter.string(from: hourDate)

                let hourTemp = entry["temp"] as? Double ?? 0
                let hourWeather = (entry["weather"] as? [[String: Any]])?.first
                let hourConditions = (hourWeather?["description"] as? String ?? "Unknown").capitalized
                let hourIcon = hourWeather?["icon"] as? String ?? "03d"
                let hourPop = entry["pop"] as? Double ?? 0

                hourlyForecasts.append(HourlyForecast(
                    hour: hourLabel,
                    temp: hourTemp,
                    conditions: hourConditions,
                    iconCode: hourIcon,
                    pop: hourPop
                ))
            }

            // Plain text for Claude (includes high/low)
            var textLines = [
                "Current Weather for \(cityName):",
                "• Conditions: \(description)",
                "• Temperature: \(String(format: "%.1f", temp))°F (feels like \(String(format: "%.1f", feelsLike))°F)"
            ]
            if let high = high, let low = low {
                textLines.append("• High: \(String(format: "%.0f", high))°F / Low: \(String(format: "%.0f", low))°F")
            }
            textLines.append("• Humidity: \(humidity)%")
            textLines.append("• Wind Speed: \(String(format: "%.1f", windSpeed)) mph")
            let textForLLM = textLines.joined(separator: "\n")

            // Structured data for UI card
            let weatherCardData = WeatherData(
                city: cityName,
                temp: temp,
                feelsLike: feelsLike,
                conditions: description,
                humidity: humidity,
                windSpeed: windSpeed,
                iconCode: currentIconCode,
                high: high,
                low: low,
                hourlyForecast: hourlyForecasts,
                observationTime: observationTime,
                timezoneOffset: timezoneOffset
            )

            return .weather(text: textForLLM, data: weatherCardData)

        } catch {
            return .plain("Weather error: \(error.localizedDescription)")
        }
    }
}

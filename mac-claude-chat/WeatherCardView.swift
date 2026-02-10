//
//  WeatherCardView.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 1 decomposition
//

import SwiftUI

// MARK: - Weather Card View

struct WeatherCardView: View {
    let data: WeatherData

    /// Condition-aware gradient based on OWM icon code
    /// All gradients are dark enough for white text readability
    private var backgroundGradient: LinearGradient {
        let base = String(data.iconCode.prefix(2))
        let isNight = data.iconCode.hasSuffix("n")

        let colors: [Color]
        switch base {
        case "01":  // Clear
            colors = isNight
                ? [Color(red: 0.08, green: 0.12, blue: 0.28), Color(red: 0.12, green: 0.18, blue: 0.38)]
                : [Color(red: 0.2, green: 0.45, blue: 0.7), Color(red: 0.35, green: 0.55, blue: 0.75)]
        case "02":  // Few clouds
            colors = isNight
                ? [Color(red: 0.12, green: 0.18, blue: 0.35), Color(red: 0.22, green: 0.28, blue: 0.42)]
                : [Color(red: 0.25, green: 0.5, blue: 0.7), Color(red: 0.4, green: 0.55, blue: 0.7)]
        case "03", "04":  // Clouds
            colors = isNight
                ? [Color(red: 0.2, green: 0.22, blue: 0.26), Color(red: 0.15, green: 0.17, blue: 0.2)]
                : [Color(red: 0.4, green: 0.45, blue: 0.52), Color(red: 0.5, green: 0.55, blue: 0.6)]
        case "09", "10":  // Rain
            colors = isNight
                ? [Color(red: 0.15, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.12, blue: 0.18)]
                : [Color(red: 0.3, green: 0.4, blue: 0.52), Color(red: 0.38, green: 0.45, blue: 0.55)]
        case "11":  // Thunderstorm
            colors = isNight
                ? [Color(red: 0.18, green: 0.12, blue: 0.22), Color(red: 0.1, green: 0.08, blue: 0.14)]
                : [Color(red: 0.3, green: 0.25, blue: 0.38), Color(red: 0.22, green: 0.2, blue: 0.3)]
        case "13":  // Snow
            colors = isNight
                ? [Color(red: 0.28, green: 0.35, blue: 0.45), Color(red: 0.2, green: 0.28, blue: 0.38)]
                : [Color(red: 0.4, green: 0.5, blue: 0.62), Color(red: 0.5, green: 0.58, blue: 0.68)]
        case "50":  // Fog/mist
            colors = isNight
                ? [Color(red: 0.25, green: 0.28, blue: 0.32), Color(red: 0.35, green: 0.38, blue: 0.42)]
                : [Color(red: 0.45, green: 0.5, blue: 0.55), Color(red: 0.55, green: 0.58, blue: 0.62)]
        default:
            colors = [Color(red: 0.4, green: 0.45, blue: 0.52), Color(red: 0.5, green: 0.55, blue: 0.6)]
        }

        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// Returns a color for the weather icon based on condition
    private func weatherIconColor(for iconCode: String) -> Color {
        let base = String(iconCode.prefix(2))
        let isNight = iconCode.hasSuffix("n")
        switch base {
        case "01": return isNight ? .white : Color(red: 1.0, green: 0.85, blue: 0.0)  // bright yellow sun, white moon
        case "02": return isNight ? .white : Color(red: 1.0, green: 0.85, blue: 0.0)  // yellow sun with clouds too
        case "03", "04": return .gray    // clouds
        case "09", "10": return .cyan    // rain
        case "11": return .purple        // thunderstorm
        case "13": return .white         // snow
        case "50": return .gray          // fog/mist
        default: return .white
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // City name + observation time
            VStack(alignment: .leading, spacing: 2) {
                Text(data.city)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let obsTime = data.formattedObservationTime {
                    Text("as of \(obsTime)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Main row: icon + temperature
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: data.symbolName)
                    .font(.system(size: 40))
                    .foregroundStyle(weatherIconColor(for: data.iconCode))
                    .symbolRenderingMode(.hierarchical)

                Text("\(Int(round(data.temp)))°")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white)
            }

            // Conditions
            Text(data.conditions)
                .font(.title3)
                .foregroundStyle(.white)

            // High/Low line (if available)
            if let high = data.high, let low = data.low {
                Text("High: \(Int(round(high)))°  Low: \(Int(round(low)))°")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            // Details row
            Text("Feels like \(Int(round(data.feelsLike)))° • Humidity \(data.humidity)% • Wind \(String(format: "%.0f", data.windSpeed)) mph")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

            // Hourly forecast row
            if !data.hourlyForecast.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 1)
                    .padding(.vertical, 4)

                HStack(spacing: 0) {
                    ForEach(Array(data.hourlyForecast.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .center, spacing: 4) {
                            // Hour label
                            Text(entry.hour)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))

                            // Weather icon
                            Image(systemName: entry.symbolName)
                                .font(.system(size: 20))
                                .foregroundStyle(weatherIconColor(for: entry.iconCode))
                                .symbolRenderingMode(.hierarchical)
                                .frame(height: 24)

                            // Precipitation %
                            HStack(spacing: 2) {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 8))
                                Text("\(Int(round(entry.pop * 100)))%")
                            }
                            .font(.caption2)
                            .foregroundStyle(entry.pop > 0 ? .cyan : .white.opacity(0.6))

                            // Temperature
                            Text("\(Int(round(entry.temp)))°F")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

import Foundation

final class WeatherService: Sendable {
    func fetch(city: String) async -> WeatherSnapshot? {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json") else {
            return nil
        }

        guard let geo = try? await fetchJSON(GeocodingResponse.self, from: geoURL),
              let place = geo.results?.first,
              let forecastURL = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(place.latitude)&longitude=\(place.longitude)&current=temperature_2m,weather_code,is_day") else {
            return nil
        }

        guard let forecast = try? await fetchJSON(ForecastResponse.self, from: forecastURL) else {
            return nil
        }

        let descriptor = WeatherDescriptor.forCode(forecast.current.weatherCode, isDay: forecast.current.isDay == 1)
        return WeatherSnapshot(
            city: place.name,
            temperature: forecast.current.temperature,
            condition: descriptor.text,
            symbol: descriptor.symbol,
            isDay: forecast.current.isDay == 1
        )
    }

    private func fetchJSON<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct GeocodingResponse: Decodable {
    struct Place: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }
    let results: [Place]?
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }
    let current: Current
}

private enum WeatherDescriptor {
    static func forCode(_ code: Int, isDay: Bool) -> (text: String, symbol: String) {
        switch code {
        case 0: return ("Clear", isDay ? "sun.max" : "moon.stars")
        case 1, 2: return ("Partly cloudy", isDay ? "cloud.sun" : "cloud.moon")
        case 3: return ("Overcast", "cloud")
        case 45, 48: return ("Foggy", "cloud.fog")
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle")
        case 61, 63, 65, 66, 67: return ("Rainy", "cloud.rain")
        case 71, 73, 75, 77: return ("Snow", "cloud.snow")
        case 80, 81, 82: return ("Rain showers", "cloud.heavyrain")
        case 85, 86: return ("Snow showers", "cloud.snow")
        case 95: return ("Thunderstorm", "cloud.bolt.rain")
        case 96, 99: return ("Thunderstorm", "cloud.bolt.rain")
        default: return ("—", "cloud")
        }
    }
}

final class StockService: Sendable {
    func fetch(symbol: String) async -> StockSnapshot? {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.isEmpty == false,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d") else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let meta = response.chart.result?.first?.meta,
              let price = meta.regularMarketPrice else {
            return nil
        }

        let previous = meta.chartPreviousClose ?? meta.previousClose ?? price
        let change = previous == 0 ? 0 : (price - previous) / previous * 100
        return StockSnapshot(
            symbol: meta.symbol ?? trimmed,
            price: price,
            changePercent: change,
            currency: meta.currency ?? "USD"
        )
    }
}

private struct ChartResponse: Decodable {
    struct Chart: Decodable {
        struct Result: Decodable {
            struct Meta: Decodable {
                let symbol: String?
                let currency: String?
                let regularMarketPrice: Double?
                let previousClose: Double?
                let chartPreviousClose: Double?
            }
            let meta: Meta
        }
        let result: [Result]?
    }
    let chart: Chart
}

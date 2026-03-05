import Foundation

struct LiveFlightsSearchModule: SearchModule {
    func search(_ input: SearchInput) async -> [FlightOption] {
        []
    }
}

struct LiveRestaurantsSearchModule: SearchModule {
    let config: TravelAPIConfig

    init(config: TravelAPIConfig) {
        self.config = config
    }

    func search(_ input: SearchInput) async -> [RestaurantOption] {
        guard config.hasGeoapify else {
            return []
        }

        guard let url = makeGeoapifyURL(input: input, categories: "catering.restaurant", key: config.geoapifyAPIKey) else {
            return []
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }

            let decoded = try JSONDecoder().decode(GeoapifyPlacesResponse.self, from: data)
            let mapped = decoded.features.compactMap { feature -> RestaurantOption? in
                guard let name = feature.properties.name, !name.isEmpty else { return nil }
                let categories = feature.properties.categories?.joined(separator: ", ") ?? "Restaurant"
                let price = Self.estimatedPrice(key: name, budget: input.budget)
                return RestaurantOption(id: UUID(), name: name, cuisine: categories, estimatedCost: price)
            }

            return Array(mapped.prefix(8))
        } catch {
            return []
        }
    }

    private static func estimatedPrice(key: String, budget: Double) -> Double {
        let base = Double(stableBucket(for: key, modulo: 30)) + 20
        return min(max(base, 15), max(20, budget / 8))
    }
}

struct LiveActivitiesSearchModule: SearchModule {
    let config: TravelAPIConfig

    init(config: TravelAPIConfig) {
        self.config = config
    }

    func search(_ input: SearchInput) async -> [ActivityOption] {
        guard config.hasGeoapify else {
            return []
        }

        let categories = "tourism.sights,entertainment"
        guard let url = makeGeoapifyURL(input: input, categories: categories, key: config.geoapifyAPIKey) else {
            return []
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }

            let decoded = try JSONDecoder().decode(GeoapifyPlacesResponse.self, from: data)
            let mapped = decoded.features.compactMap { feature -> ActivityOption? in
                guard let title = feature.properties.name, !title.isEmpty else { return nil }
                let category = feature.properties.categories?.first ?? "activity"
                let price = Double(stableBucket(for: "\(title)|\(category)", modulo: 45)) + 10
                return ActivityOption(id: UUID(), title: title, category: category, estimatedCost: min(price, max(15, input.budget / 10)))
            }

            return Array(mapped.prefix(8))
        } catch {
            return []
        }
    }
}

private func makeGeoapifyURL(input: SearchInput, categories: String, key: String) -> URL? {
    var components = URLComponents(string: "https://api.geoapify.com/v2/places")
    var queryItems: [URLQueryItem] = [
        URLQueryItem(name: "categories", value: categories),
        URLQueryItem(name: "limit", value: "8"),
        URLQueryItem(name: "apiKey", value: key)
    ]

    if let lon = input.longitude, let lat = input.latitude {
        queryItems.append(URLQueryItem(name: "filter", value: "circle:\(lon),\(lat),20000"))
        queryItems.append(URLQueryItem(name: "bias", value: "proximity:\(lon),\(lat)"))
    } else if let destinationName = input.destinationName {
        queryItems.append(URLQueryItem(name: "text", value: destinationName))
    } else {
        queryItems.append(URLQueryItem(name: "text", value: input.query))
    }

    components?.queryItems = queryItems
    return components?.url
}

private func stableBucket(for key: String, modulo: Int) -> Int {
    guard modulo > 0 else { return 0 }

    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in key.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return Int(hash % UInt64(modulo))
}

private struct GeoapifyPlacesResponse: Decodable {
    struct Feature: Decodable {
        struct Properties: Decodable {
            let name: String?
            let categories: [String]?
        }

        let properties: Properties
    }

    let features: [Feature]
}

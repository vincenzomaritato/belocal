import Foundation

struct AttractionCardLiveInfo: Sendable, Hashable {
    let address: String?
    let rating: Double?
    let reviewCount: Int?
    let openNow: Bool?
    let placeSummary: String?
    let placeTypes: [String]
    let priceLevel: String?
    let websiteURL: URL?
    let phoneNumber: String?
    let weatherSummary: String?
    let temperatureC: Double?
    let mapsURL: URL?
    let wikiTitle: String?
    let wikiSummary: String?
    let wikiImageURL: URL?
    let wikiArticleURL: URL?
    let nearbySpots: [String]
}

struct AttractionCardLiveInfoService {
    let config: TravelAPIConfig
    let session: URLSession

    init(config: TravelAPIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetch(
        attractionName: String,
        destination: String?
    ) async -> AttractionCardLiveInfo? {
        let normalizedName = trimmedNonEmpty(attractionName) ?? attractionName
        let normalizedDestination = trimmedNonEmpty(destination)
        let query = normalizedDestination.map { "\(normalizedName), \($0)" } ?? normalizedName

        let place = await fetchPlace(query: query)

        var weather: OpenMeteoResponse?
        if let latitude = place?.latitude, let longitude = place?.longitude {
            weather = await fetchWeather(latitude: latitude, longitude: longitude)
        }

        let wikiInfo = await fetchWikipediaInfo(
            attractionName: normalizedName,
            destination: normalizedDestination,
            placeName: place?.displayName
        )

        let nearbySpots: [String]
        if let latitude = place?.latitude, let longitude = place?.longitude {
            nearbySpots = await fetchGeoapifyNearby(
                latitude: latitude,
                longitude: longitude,
                excluding: normalizedName
            )
        } else {
            nearbySpots = []
        }

        guard place != nil || weather != nil || wikiInfo != nil || !nearbySpots.isEmpty else {
            return nil
        }

        let weatherCode: Int? = weather?.current?.weatherCode ?? weather?.currentWeather?.weathercode
        let isDay: Bool? = {
            if let dayFlag = weather?.current?.isDay { return dayFlag == 1 }
            if let dayFlag = weather?.currentWeather?.isDay { return dayFlag == 1 }
            return nil
        }()
        let temperature: Double? = weather?.current?.temperature2m ?? weather?.currentWeather?.temperature

        let wikiImage: URL?
        if let image = wikiInfo?.imageURL {
            wikiImage = image
        } else {
            wikiImage = await fetchWikimediaCommonsImage(
                query: "\(normalizedName) \(normalizedDestination ?? "")"
            )
        }

        return AttractionCardLiveInfo(
            address: place?.formattedAddress,
            rating: place?.rating,
            reviewCount: place?.userRatingCount,
            openNow: place?.openNow,
            placeSummary: place?.editorialSummary,
            placeTypes: place?.types ?? [],
            priceLevel: readablePriceLevel(place?.priceLevelRaw),
            websiteURL: place?.websiteURL,
            phoneNumber: place?.phoneNumber,
            weatherSummary: weatherCode.flatMap { weatherDescription(for: $0, isDay: isDay) },
            temperatureC: temperature,
            mapsURL: mapsURL(from: place?.googleMapsURI, query: query),
            wikiTitle: wikiInfo?.title,
            wikiSummary: wikiInfo?.summary,
            wikiImageURL: wikiImage,
            wikiArticleURL: wikiInfo?.articleURL,
            nearbySpots: Array(nearbySpots.prefix(5))
        )
    }

    private func fetchPlace(query: String) async -> PlaceSeed? {
        if let google = await fetchPlaceWithGoogle(query: query) {
            return google
        }
        return await fetchPlaceWithGeoapify(query: query)
    }

    private func fetchPlaceWithGoogle(query: String) async -> PlaceSeed? {
        guard config.hasGooglePlaces else { return nil }
        guard let url = URL(string: "https://places.googleapis.com/v1/places:searchText") else { return nil }

        let payload = GooglePlaceSearchRequest(
            textQuery: query,
            maxResultCount: 1,
            languageCode: preferredLanguageCode
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(config.googlePlacesAPIKey, forHTTPHeaderField: "X-Goog-Api-Key")
            request.setValue(
                "places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.currentOpeningHours.openNow,places.googleMapsUri,places.editorialSummary,places.websiteUri,places.nationalPhoneNumber,places.priceLevel,places.types",
                forHTTPHeaderField: "X-Goog-FieldMask"
            )
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            guard let place = try JSONDecoder().decode(GooglePlaceSearchResponse.self, from: data).places?.first else {
                return nil
            }

            return PlaceSeed(
                displayName: place.displayName?.text,
                formattedAddress: place.formattedAddress,
                latitude: place.location?.latitude,
                longitude: place.location?.longitude,
                rating: place.rating,
                userRatingCount: place.userRatingCount,
                openNow: place.currentOpeningHours?.openNow,
                editorialSummary: place.editorialSummary?.text,
                websiteURL: place.websiteUri.flatMap(URL.init(string:)),
                phoneNumber: trimmedNonEmpty(place.nationalPhoneNumber ?? ""),
                priceLevelRaw: place.priceLevel,
                types: place.types ?? [],
                googleMapsURI: place.googleMapsUri
            )
        } catch {
            return nil
        }
    }

    private func fetchPlaceWithGeoapify(query: String) async -> PlaceSeed? {
        guard config.hasGeoapify else { return nil }

        var components = URLComponents(string: "https://api.geoapify.com/v1/geocode/search")
        components?.queryItems = [
            URLQueryItem(name: "text", value: query),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "apiKey", value: config.geoapifyAPIKey)
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            guard let feature = try JSONDecoder().decode(GeoapifyGeocodeResponse.self, from: data).features.first else {
                return nil
            }

            let lat = feature.geometry.coordinates.count > 1 ? feature.geometry.coordinates[1] : nil
            let lon = feature.geometry.coordinates.count > 1 ? feature.geometry.coordinates[0] : nil
            return PlaceSeed(
                displayName: feature.properties.name,
                formattedAddress: feature.properties.formatted,
                latitude: lat,
                longitude: lon,
                rating: nil,
                userRatingCount: nil,
                openNow: nil,
                editorialSummary: nil,
                websiteURL: nil,
                phoneNumber: nil,
                priceLevelRaw: nil,
                types: [],
                googleMapsURI: nil
            )
        } catch {
            return nil
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double) async -> OpenMeteoResponse? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private func fetchGeoapifyNearby(
        latitude: Double,
        longitude: Double,
        excluding attractionName: String
    ) async -> [String] {
        guard config.hasGeoapify else { return [] }

        var components = URLComponents(string: "https://api.geoapify.com/v2/places")
        components?.queryItems = [
            URLQueryItem(name: "categories", value: "tourism.sights,entertainment,museum"),
            URLQueryItem(name: "filter", value: "circle:\(longitude),\(latitude),1500"),
            URLQueryItem(name: "bias", value: "proximity:\(longitude),\(latitude)"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "apiKey", value: config.geoapifyAPIKey)
        ]
        guard let url = components?.url else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(GeoapifyPlacesResponse.self, from: data)
            let normalizedAttraction = normalizeKey(attractionName)
            var unique: [String] = []
            var seen = Set<String>()

            for feature in decoded.features {
                guard let name = trimmedNonEmpty(feature.properties.name) else { continue }
                let key = normalizeKey(name)
                if key == normalizedAttraction || seen.contains(key) { continue }
                seen.insert(key)
                unique.append(name)
                if unique.count >= 5 { break }
            }
            return unique
        } catch {
            return []
        }
    }

    private func fetchWikipediaInfo(
        attractionName: String,
        destination: String?,
        placeName: String?
    ) async -> WikipediaAttractionInfo? {
        let titleCandidates = wikipediaTitleCandidates(
            attractionName: attractionName,
            destination: destination,
            placeName: placeName
        )

        for candidate in titleCandidates {
            if let summary = await fetchWikipediaSummary(title: candidate) {
                return summary
            }
        }

        let searchQuery = [attractionName, destination]
            .compactMap { trimmedNonEmpty($0 ?? "") }
            .joined(separator: " ")
        if let topTitle = await searchWikipediaTopTitle(query: searchQuery),
           let summary = await fetchWikipediaSummary(title: topTitle) {
            return summary
        }

        return nil
    }

    private func wikipediaTitleCandidates(
        attractionName: String,
        destination: String?,
        placeName: String?
    ) -> [String] {
        var candidates: [String] = []

        if let placeName = trimmedNonEmpty(placeName ?? "") {
            candidates.append(placeName)
        }

        candidates.append(attractionName)

        if let destination = trimmedNonEmpty(destination ?? "") {
            candidates.append("\(attractionName), \(destination)")
            candidates.append("\(attractionName) (\(destination))")
        }

        var unique: [String] = []
        var seen = Set<String>()
        for value in candidates {
            let key = normalizeKey(value)
            if seen.contains(key) { continue }
            seen.insert(key)
            unique.append(value)
        }
        return unique
    }

    private func fetchWikipediaSummary(title: String) async -> WikipediaAttractionInfo? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        let languages = Array(NSOrderedSet(array: [preferredLanguageCode, "en"]).compactMap { $0 as? String })

        for languageCode in languages {
            guard let url = URL(string: "https://\(languageCode).wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    continue
                }

                let decoded = try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)
                guard decoded.type != "disambiguation" else { continue }

                let summary = decoded.extract.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !summary.isEmpty else { continue }

                return WikipediaAttractionInfo(
                    title: decoded.title,
                    summary: summary,
                    imageURL: decoded.thumbnail?.source.flatMap(URL.init(string:)),
                    articleURL: decoded.contentURLs?.desktop?.page.flatMap(URL.init(string:))
                )
            } catch {
                continue
            }
        }

        return nil
    }

    private func searchWikipediaTopTitle(query: String) async -> String? {
        guard let normalized = trimmedNonEmpty(query) else { return nil }
        let languages = Array(NSOrderedSet(array: [preferredLanguageCode, "en"]).compactMap { $0 as? String })

        for languageCode in languages {
            var components = URLComponents(string: "https://\(languageCode).wikipedia.org/w/api.php")
            components?.queryItems = [
                URLQueryItem(name: "action", value: "opensearch"),
                URLQueryItem(name: "search", value: normalized),
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "namespace", value: "0"),
                URLQueryItem(name: "format", value: "json")
            ]
            guard let url = components?.url else { continue }

            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    continue
                }

                guard let payload = try JSONSerialization.jsonObject(with: data) as? [Any],
                      payload.count > 1,
                      let titles = payload[1] as? [String],
                      let first = titles.first else {
                    continue
                }
                return first
            } catch {
                continue
            }
        }

        return nil
    }

    private func fetchWikimediaCommonsImage(query: String) async -> URL? {
        guard let normalized = trimmedNonEmpty(query) else { return nil }
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: normalized),
            URLQueryItem(name: "gsrlimit", value: "1"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "1000")
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(WikimediaCommonsResponse.self, from: data)
            guard let pages = decoded.query?.pages else { return nil }
            for page in pages.values {
                if let source = page.thumbnail?.source, let imageURL = URL(string: source) {
                    return imageURL
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func weatherDescription(for code: Int, isDay: Bool?) -> String {
        switch code {
        case 0: return (isDay == false) ? L10n.tr("Clear night") : L10n.tr("Clear sky")
        case 1: return L10n.tr("Mainly clear")
        case 2: return L10n.tr("Partly cloudy")
        case 3: return L10n.tr("Overcast")
        case 45, 48: return L10n.tr("Fog")
        case 51, 53, 55: return L10n.tr("Drizzle")
        case 56, 57: return L10n.tr("Freezing drizzle")
        case 61, 63, 65: return L10n.tr("Rain")
        case 66, 67: return L10n.tr("Freezing rain")
        case 71, 73, 75, 77: return L10n.tr("Snow")
        case 80, 81, 82: return L10n.tr("Rain showers")
        case 85, 86: return L10n.tr("Snow showers")
        case 95: return L10n.tr("Thunderstorm")
        case 96, 99: return L10n.tr("Thunderstorm with hail")
        default: return L10n.tr("Variable weather")
        }
    }

    private func mapsURL(from googleMapsURI: String?, query: String) -> URL? {
        if let googleMapsURI, let deeplink = URL(string: googleMapsURI) {
            return deeplink
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)")
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readablePriceLevel(_ raw: String?) -> String? {
        guard let raw = trimmedNonEmpty(raw) else { return nil }
        switch raw {
        case "PRICE_LEVEL_FREE": return L10n.tr("Free")
        case "PRICE_LEVEL_INEXPENSIVE": return "€"
        case "PRICE_LEVEL_MODERATE": return "€€"
        case "PRICE_LEVEL_EXPENSIVE": return "€€€"
        case "PRICE_LEVEL_VERY_EXPENSIVE": return "€€€€"
        default: return nil
        }
    }

    private var preferredLanguageCode: String {
        L10n.preferredLanguageCode
    }
}

private struct PlaceSeed {
    let displayName: String?
    let formattedAddress: String?
    let latitude: Double?
    let longitude: Double?
    let rating: Double?
    let userRatingCount: Int?
    let openNow: Bool?
    let editorialSummary: String?
    let websiteURL: URL?
    let phoneNumber: String?
    let priceLevelRaw: String?
    let types: [String]
    let googleMapsURI: String?
}

private struct GooglePlaceSearchRequest: Encodable {
    let textQuery: String
    let maxResultCount: Int
    let languageCode: String
}

private struct GooglePlaceSearchResponse: Decodable {
    let places: [GooglePlaceCardResult]?
}

private struct GooglePlaceCardResult: Decodable {
    struct DisplayName: Decodable {
        let text: String?
    }

    struct EditorialSummary: Decodable {
        let text: String?
    }

    struct Location: Decodable {
        let latitude: Double
        let longitude: Double
    }

    struct OpeningHours: Decodable {
        let openNow: Bool?
    }

    let displayName: DisplayName?
    let formattedAddress: String?
    let location: Location?
    let rating: Double?
    let userRatingCount: Int?
    let currentOpeningHours: OpeningHours?
    let googleMapsUri: String?
    let editorialSummary: EditorialSummary?
    let websiteUri: String?
    let nationalPhoneNumber: String?
    let priceLevel: String?
    let types: [String]?
}

private struct GeoapifyGeocodeResponse: Decodable {
    struct Feature: Decodable {
        struct Geometry: Decodable {
            let coordinates: [Double]
        }

        struct Properties: Decodable {
            let name: String?
            let formatted: String?
        }

        let geometry: Geometry
        let properties: Properties
    }

    let features: [Feature]
}

private struct GeoapifyPlacesResponse: Decodable {
    struct Feature: Decodable {
        struct Properties: Decodable {
            let name: String?
        }

        let properties: Properties
    }

    let features: [Feature]
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double?
        let weatherCode: Int?
        let isDay: Int?

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    struct CurrentWeather: Decodable {
        let temperature: Double?
        let weathercode: Int?
        let isDay: Int?

        enum CodingKeys: String, CodingKey {
            case temperature
            case weathercode
            case isDay = "is_day"
        }
    }

    let current: Current?
    let currentWeather: CurrentWeather?

    enum CodingKeys: String, CodingKey {
        case current
        case currentWeather = "current_weather"
    }
}

private struct WikipediaAttractionInfo: Sendable, Hashable {
    let title: String
    let summary: String
    let imageURL: URL?
    let articleURL: URL?
}

private struct WikipediaSummaryResponse: Decodable {
    struct Thumbnail: Decodable {
        let source: String?
    }

    struct ContentURLs: Decodable {
        struct Desktop: Decodable {
            let page: String?
        }

        let desktop: Desktop?
    }

    let title: String
    let extract: String
    let type: String?
    let thumbnail: Thumbnail?
    let contentURLs: ContentURLs?

    enum CodingKeys: String, CodingKey {
        case title
        case extract
        case type
        case thumbnail
        case contentURLs = "content_urls"
    }
}

private struct WikimediaCommonsResponse: Decodable {
    struct Query: Decodable {
        struct Page: Decodable {
            struct Thumbnail: Decodable {
                let source: String?
            }

            let thumbnail: Thumbnail?
        }

        let pages: [String: Page]
    }

    let query: Query?
}

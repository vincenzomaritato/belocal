import CoreLocation
import Foundation
import MapKit

struct ExplorerCity: Identifiable, Hashable {
    let name: String
    let country: String
    let region: String?
    let latitude: Double
    let longitude: Double

    var id: String {
        "\(name.lowercased())|\(country.lowercased())|\(latitude)|\(longitude)"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var label: String {
        if let region, !region.isEmpty, region.caseInsensitiveCompare(country) != .orderedSame {
            return "\(name), \(region), \(country)"
        }
        return "\(name), \(country)"
    }
}

struct CityWikiInfo: Equatable {
    let title: String
    let subtitle: String
    let summary: String
    let articleURL: URL?
    let imageURL: URL?
}

enum CityPlaceCategory: String, CaseIterable, Hashable {
    case attractions
    case restaurants
    case essentials

    var title: String {
        switch self {
        case .attractions: return "Attractions"
        case .restaurants: return "Restaurants"
        case .essentials: return "Essentials"
        }
    }

    func mapQuery(for city: ExplorerCity) -> String {
        switch self {
        case .attractions:
            return "Top attractions in \(city.label)"
        case .restaurants:
            return "Best restaurants in \(city.label)"
        case .essentials:
            return "Transport hubs and useful places in \(city.label)"
        }
    }

    var googleIncludedType: String? {
        switch self {
        case .attractions:
            return "tourist_attraction"
        case .restaurants:
            return "restaurant"
        case .essentials:
            return "transit_station"
        }
    }

    var geoapifyCategories: String {
        switch self {
        case .attractions:
            return "tourism.sights,entertainment,tourism,museum"
        case .restaurants:
            return "catering.restaurant,catering.cafe,catering.bar"
        case .essentials:
            return "public_transport,accommodation.hotel,tourism.information,service.vehicle.parking"
        }
    }
}

struct CityPlace: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let distanceLabel: String?
    let deeplink: URL?
    let provider: String
    let category: CityPlaceCategory
    let rating: Double?
    let reviewCount: Int?
    let priceLevel: Int?
    let openNow: Bool?
    let placeType: String?
    let personalizationScore: Double?
    let personalizationReason: String?
}

struct CityExplorerService {
    let config: TravelAPIConfig
    let session: URLSession

    private struct LocalCityCenter {
        let name: String
        let countryCode: String
        let latitude: Double
        let longitude: Double
        let population: Int
    }

    private static let localCityCenters: [LocalCityCenter] = loadLocalCityCenters()
    private static let localCityCentersByKey: [String: [LocalCityCenter]] = {
        Dictionary(grouping: localCityCenters) { city in
            cityKey(name: city.name, countryCode: city.countryCode)
        }
    }()
    private static let countryNameByCode: [String: String] = {
        let englishLocale = Locale(identifier: "en_US_POSIX")
        var result: [String: String] = [:]
        for code in Locale.Region.isoRegions.map(\.identifier) {
            let upper = code.uppercased()
            if let name = Locale.current.localizedString(forRegionCode: upper)
                ?? englishLocale.localizedString(forRegionCode: upper) {
                result[upper] = name
            }
        }
        return result
    }()
    private static let countryCodeByNormalizedName: [String: String] = {
        let englishLocale = Locale(identifier: "en_US_POSIX")
        var result: [String: String] = [:]
        for code in Locale.Region.isoRegions.map(\.identifier) {
            let upper = code.uppercased()
            if let localized = Locale.current.localizedString(forRegionCode: upper) {
                result[normalize(localized)] = upper
            }
            if let english = englishLocale.localizedString(forRegionCode: upper) {
                result[normalize(english)] = upper
            }
        }
        return result
    }()

    init(config: TravelAPIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func searchCity(query: String) async -> ExplorerCity? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if config.hasGooglePlaces, let googleCity = await searchCityWithGoogle(query: trimmed) {
            return canonicalizedCity(googleCity, near: googleCity.coordinate) ?? googleCity
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = .address

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let city = response.mapItems.compactMap(mapItemToCity).first else { return nil }
            return canonicalizedCity(city, near: city.coordinate) ?? city
        } catch {
            return nil
        }
    }

    func cityForCoordinate(_ coordinate: CLLocationCoordinate2D) async -> ExplorerCity? {
        if let snappedCity = nearestLocalCity(to: coordinate, maxDistanceKm: 22) {
            return snappedCity
        }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            do {
                let mapItems = try await request.mapItems
                guard let mapItem = mapItems.first else { return nil }
                guard let city = mapItemToCity(mapItem) else { return nil }
                return canonicalizedCity(city, near: coordinate) ?? city
            } catch {
                return nil
            }
        } else {
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                guard let placemark = placemarks.first else { return nil }
                guard let city = cityFromPlacemark(placemark, fallbackCoordinate: coordinate) else { return nil }
                return canonicalizedCity(city, near: coordinate) ?? city
            } catch {
                return nil
            }
        }
    }

    func fetchWikipediaInfo(for city: ExplorerCity) async -> CityWikiInfo? {
        let candidates = wikiTitleCandidates(for: city)

        for candidate in candidates {
            guard let encoded = candidate.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { continue }
            guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { continue }

            do {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }

                let decoded = try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)
                guard !decoded.extract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                return CityWikiInfo(
                    title: decoded.title,
                    subtitle: decoded.description ?? city.label,
                    summary: decoded.extract,
                    articleURL: decoded.contentURLs?.desktop?.page.flatMap(URL.init(string:)),
                    imageURL: decoded.thumbnail?.source.flatMap(URL.init(string:))
                )
            } catch {
                continue
            }
        }

        return nil
    }

    func fetchPlaces(for city: ExplorerCity, category: CityPlaceCategory) async -> [CityPlace] {
        var merged: [CityPlace] = []

        if config.hasGooglePlaces {
            merged = await fetchGooglePlaces(for: city, category: category)
        }

        if merged.isEmpty {
            merged = await fetchMapKitPlaces(for: city, category: category)
        }

        if config.hasGeoapify {
            let geoapifyPlaces = await fetchGeoapifyPlaces(for: city, category: category)
            merged = deduplicating(merged + geoapifyPlaces)
        }

        if merged.isEmpty {
            return fallbackPlaces(for: city, category: category)
        }

        return Array(merged.prefix(8))
    }

    private func fetchMapKitPlaces(for city: ExplorerCity, category: CityPlaceCategory) async -> [CityPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.mapQuery(for: city)
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: city.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            let center = CLLocation(latitude: city.latitude, longitude: city.longitude)
            return response.mapItems.prefix(12).compactMap { item in
                mapItemToPlace(item, center: center, category: category)
            }
        } catch {
            return []
        }
    }

    private func searchCityWithGoogle(query: String) async -> ExplorerCity? {
        let payload = GoogleTextSearchRequest(
            textQuery: query,
            maxResultCount: 5,
            languageCode: "en",
            locationBias: nil,
            includedType: "locality",
            strictTypeFiltering: true
        )

        let response = await performGoogleTextSearch(
            payload,
            fieldMask: "places.id,places.displayName,places.formattedAddress,places.location,places.addressComponents,places.types"
        )
        let places = response?.places ?? []

        for place in places {
            if let types = place.types, types.contains("locality"), let city = googlePlaceToCity(place) {
                return city
            }
        }

        for place in places {
            if let city = googlePlaceToCity(place) {
                return city
            }
        }

        return nil
    }

    private func fetchGooglePlaces(for city: ExplorerCity, category: CityPlaceCategory) async -> [CityPlace] {
        let primary = await fetchGooglePlaces(
            for: city,
            category: category,
            includedType: category.googleIncludedType
        )
        if !primary.isEmpty {
            return primary
        }

        return await fetchGooglePlaces(
            for: city,
            category: category,
            includedType: nil
        )
    }

    private func fetchGooglePlaces(
        for city: ExplorerCity,
        category: CityPlaceCategory,
        includedType: String?
    ) async -> [CityPlace] {
        let payload = GoogleTextSearchRequest(
            textQuery: category.mapQuery(for: city),
            maxResultCount: 10,
            languageCode: "en",
            locationBias: GoogleLocationBias(
                circle: GoogleCircle(
                    center: GoogleLatLng(latitude: city.latitude, longitude: city.longitude),
                    radius: 15_000
                )
            ),
            includedType: includedType,
            strictTypeFiltering: false
        )

        let response = await performGoogleTextSearch(
            payload,
            fieldMask: "places.id,places.displayName,places.formattedAddress,places.location,places.googleMapsUri,places.types,places.rating,places.userRatingCount,places.priceLevel,places.currentOpeningHours.openNow,places.primaryTypeDisplayName"
        )
        let center = CLLocation(latitude: city.latitude, longitude: city.longitude)

        return (response?.places ?? []).prefix(12).compactMap { place in
            googlePlaceToPlace(place, center: center, category: category)
        }
    }

    private func performGoogleTextSearch(
        _ payload: GoogleTextSearchRequest,
        fieldMask: String
    ) async -> GoogleTextSearchResponse? {
        guard config.hasGooglePlaces else { return nil }
        guard let url = URL(string: "https://places.googleapis.com/v1/places:searchText") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(config.googlePlacesAPIKey, forHTTPHeaderField: "X-Goog-Api-Key")
            request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            return try JSONDecoder().decode(GoogleTextSearchResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private func googlePlaceToPlace(
        _ place: GooglePlaceResult,
        center: CLLocation,
        category: CityPlaceCategory
    ) -> CityPlace? {
        guard let name = place.displayName?.text?.trimmedNonEmpty else { return nil }
        guard let location = place.location else { return nil }

        let subtitle = place.formattedAddress?.trimmedNonEmpty
            ?? place.types?.first?.replacingOccurrences(of: "_", with: " ").capitalized
            ?? "Local place"

        let point = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let distance = point.distance(from: center)
        let distanceLabel: String = distance < 1000
            ? "\(Int(distance.rounded())) m"
            : String(format: "%.1f km", distance / 1000)

        let deeplink = place.googleMapsUri.flatMap(URL.init(string:))
            ?? googleMapsSearchURL(query: "\(name) near \(center.coordinate.latitude),\(center.coordinate.longitude)")

        return CityPlace(
            id: "\(place.id ?? name.lowercased())|google",
            name: name,
            subtitle: subtitle,
            distanceLabel: distanceLabel,
            deeplink: deeplink,
            provider: "Google Places",
            category: category,
            rating: place.rating,
            reviewCount: place.userRatingCount,
            priceLevel: place.priceLevel,
            openNow: place.currentOpeningHours?.openNow,
            placeType: place.primaryTypeDisplayName?.text?.trimmedNonEmpty,
            personalizationScore: nil,
            personalizationReason: nil
        )
    }

    private func googlePlaceToCity(_ place: GooglePlaceResult) -> ExplorerCity? {
        guard let name = place.displayName?.text?.trimmedNonEmpty else { return nil }
        guard let location = place.location else { return nil }

        let country = place.addressComponents?
            .first(where: { $0.types?.contains("country") == true })?
            .longText?
            .trimmedNonEmpty
            ?? place.formattedAddress?
            .split(separator: ",")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmedNonEmpty

        let region = place.addressComponents?
            .first(where: { $0.types?.contains("administrative_area_level_1") == true })?
            .longText?
            .trimmedNonEmpty

        guard let country else { return nil }

        return ExplorerCity(
            name: name,
            country: country,
            region: region,
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    private func mapItemToPlace(
        _ mapItem: MKMapItem,
        center: CLLocation,
        category: CityPlaceCategory
    ) -> CityPlace? {
        guard let name = mapItem.name, !name.isEmpty else { return nil }

        let coordinate = mapItemCoordinate(mapItem)
        let subtitle = mapItemSubtitle(mapItem)
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let distance = location.distance(from: center)
        let distanceLabel: String = distance < 1000
            ? "\(Int(distance.rounded())) m"
            : String(format: "%.1f km", distance / 1000)

        let deeplink = appleMapsURL(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: name
        )

        return CityPlace(
            id: "\(name.lowercased())|\(coordinate.latitude)|\(coordinate.longitude)|mapkit",
            name: name,
            subtitle: subtitle,
            distanceLabel: distanceLabel,
            deeplink: deeplink,
            provider: "Apple Maps",
            category: category,
            rating: nil,
            reviewCount: nil,
            priceLevel: nil,
            openNow: nil,
            placeType: nil,
            personalizationScore: nil,
            personalizationReason: nil
        )
    }

    private func fetchGeoapifyPlaces(for city: ExplorerCity, category: CityPlaceCategory) async -> [CityPlace] {
        guard let url = makeGeoapifyURL(for: city, category: category) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }

            let decoded = try JSONDecoder().decode(GeoapifyPlacesResponse.self, from: data)
            let center = CLLocation(latitude: city.latitude, longitude: city.longitude)

            return decoded.features.prefix(12).compactMap { feature in
                guard let name = feature.properties.name, !name.isEmpty else { return nil }
                guard let lon = feature.geometry.coordinates.first, feature.geometry.coordinates.count > 1 else { return nil }
                let lat = feature.geometry.coordinates[1]
                let location = CLLocation(latitude: lat, longitude: lon)
                let distance = location.distance(from: center)
                let distanceLabel: String = distance < 1000
                    ? "\(Int(distance.rounded())) m"
                    : String(format: "%.1f km", distance / 1000)

                let subtitle = feature.properties.formatted
                    ?? feature.properties.categories?.first?.replacingOccurrences(of: ".", with: " ").capitalized
                    ?? "Local place"

                return CityPlace(
                    id: "\(name.lowercased())|\(lat)|\(lon)|geoapify",
                    name: name,
                    subtitle: subtitle,
                    distanceLabel: distanceLabel,
                    deeplink: appleMapsURL(latitude: lat, longitude: lon, name: name),
                    provider: "Geoapify",
                    category: category,
                    rating: nil,
                    reviewCount: nil,
                    priceLevel: nil,
                    openNow: nil,
                    placeType: feature.properties.categories?.first,
                    personalizationScore: nil,
                    personalizationReason: nil
                )
            }
        } catch {
            return []
        }
    }

    private func makeGeoapifyURL(for city: ExplorerCity, category: CityPlaceCategory) -> URL? {
        var components = URLComponents(string: "https://api.geoapify.com/v2/places")
        components?.queryItems = [
            URLQueryItem(name: "categories", value: category.geoapifyCategories),
            URLQueryItem(name: "filter", value: "circle:\(city.longitude),\(city.latitude),15000"),
            URLQueryItem(name: "bias", value: "proximity:\(city.longitude),\(city.latitude)"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "apiKey", value: config.geoapifyAPIKey)
        ]
        return components?.url
    }

    private func fallbackPlaces(for city: ExplorerCity, category: CityPlaceCategory) -> [CityPlace] {
        let searchLabel: String
        switch category {
        case .attractions:
            searchLabel = "attractions"
        case .restaurants:
            searchLabel = "restaurants"
        case .essentials:
            searchLabel = "transport"
        }

        let query = "\(searchLabel) \(city.label)"
        let deeplink = config.hasGooglePlaces
            ? googleMapsSearchURL(query: query)
            : appleMapsSearchURL(query: query)

        return [
            CityPlace(
                id: "\(category.rawValue)-fallback-1-\(city.id)",
                name: "Top \(category.title)",
                subtitle: "Open map search for live results in \(city.name).",
                distanceLabel: nil,
                deeplink: deeplink,
                provider: config.hasGooglePlaces ? "Google Places" : "Apple Maps",
                category: category,
                rating: nil,
                reviewCount: nil,
                priceLevel: nil,
                openNow: nil,
                placeType: nil,
                personalizationScore: nil,
                personalizationReason: nil
            )
        ]
    }

    private func deduplicating(_ places: [CityPlace]) -> [CityPlace] {
        var seen = Set<String>()
        var deduped: [CityPlace] = []
        for place in places {
            let key = "\(place.name.lowercased())|\(place.category.rawValue)"
            guard seen.insert(key).inserted else { continue }
            deduped.append(place)
        }
        return deduped
    }

    private func appleMapsURL(latitude: Double, longitude: Double, name: String) -> URL? {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(encodedName)")
    }

    private func appleMapsSearchURL(query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    private func googleMapsSearchURL(query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)")
    }

    private func mapItemToCity(_ mapItem: MKMapItem) -> ExplorerCity? {
        let name = mapItemCityName(mapItem)
        let country = mapItemCountryName(mapItem)

        guard let name, let country, !name.isEmpty, !country.isEmpty else { return nil }
        let coordinate = mapItemCoordinate(mapItem)
        return ExplorerCity(
            name: name,
            country: country,
            region: mapItemAdministrativeArea(mapItem),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private func mapItemCoordinate(_ mapItem: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return mapItem.location.coordinate
        } else {
            return mapItem.placemark.coordinate
        }
    }

    private func mapItemSubtitle(_ mapItem: MKMapItem) -> String {
        if #available(iOS 26.0, *) {
            return mapItem.address?.shortAddress
                ?? mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
                ?? "No additional details"
        } else {
            return mapItem.placemark.title ?? mapItem.placemark.locality ?? "No additional details"
        }
    }

    private func mapItemCityName(_ mapItem: MKMapItem) -> String? {
        if #available(iOS 26.0, *) {
            return mapItem.addressRepresentations?.cityName?.trimmedNonEmpty
                ?? mapItem.name?.trimmedNonEmpty
        } else {
            let placemark = mapItem.placemark
            return (placemark.locality ?? placemark.subLocality ?? mapItem.name)?.trimmedNonEmpty
        }
    }

    private func mapItemCountryName(_ mapItem: MKMapItem) -> String? {
        if #available(iOS 26.0, *) {
            return mapItem.addressRepresentations?.regionName?.trimmedNonEmpty
        } else {
            return mapItem.placemark.country?.trimmedNonEmpty
        }
    }

    private func mapItemAdministrativeArea(_ mapItem: MKMapItem) -> String? {
        if #available(iOS 26.0, *) {
            guard let context = mapItem.addressRepresentations?.cityWithContext(.full)?.trimmedNonEmpty else { return nil }
            let parts = context
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 3 else { return nil }
            return parts[1].trimmedNonEmpty
        } else {
            return mapItem.placemark.administrativeArea?.trimmedNonEmpty
        }
    }

    private func cityFromPlacemark(_ placemark: CLPlacemark, fallbackCoordinate: CLLocationCoordinate2D) -> ExplorerCity? {
        guard
            let name = placemark.locality ?? placemark.subLocality ?? placemark.name,
            let country = placemark.country
        else { return nil }

        let coordinate = placemark.location?.coordinate ?? fallbackCoordinate
        return ExplorerCity(
            name: name,
            country: country,
            region: placemark.administrativeArea,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private func wikiTitleCandidates(for city: ExplorerCity) -> [String] {
        var candidates = [city.name]
        candidates.append("\(city.name), \(city.country)")
        if let region = city.region, !region.isEmpty {
            candidates.append("\(city.name), \(region)")
        }
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private func nearestLocalCity(
        to coordinate: CLLocationCoordinate2D,
        maxDistanceKm: Double
    ) -> ExplorerCity? {
        var nearest: (city: LocalCityCenter, distanceKm: Double)?

        for city in Self.localCityCenters {
            let distance = haversineDistanceKm(
                lat1: coordinate.latitude,
                lon1: coordinate.longitude,
                lat2: city.latitude,
                lon2: city.longitude
            )

            guard distance <= maxDistanceKm else { continue }
            if nearest == nil || distance < nearest!.distanceKm {
                nearest = (city, distance)
            }
        }

        guard let nearest else { return nil }
        return explorerCity(from: nearest.city, region: nil)
    }

    private func canonicalizedCity(
        _ city: ExplorerCity,
        near coordinate: CLLocationCoordinate2D
    ) -> ExplorerCity? {
        guard let countryCode = countryCode(forCountryName: city.country) else { return nil }
        let key = Self.cityKey(name: city.name, countryCode: countryCode)
        guard let matches = Self.localCityCentersByKey[key], !matches.isEmpty else { return nil }

        let nearest = matches.min { lhs, rhs in
            let lhsDistance = haversineDistanceKm(
                lat1: coordinate.latitude,
                lon1: coordinate.longitude,
                lat2: lhs.latitude,
                lon2: lhs.longitude
            )
            let rhsDistance = haversineDistanceKm(
                lat1: coordinate.latitude,
                lon1: coordinate.longitude,
                lat2: rhs.latitude,
                lon2: rhs.longitude
            )
            return lhsDistance < rhsDistance
        }

        guard let nearest else { return nil }
        let nearestDistance = haversineDistanceKm(
            lat1: coordinate.latitude,
            lon1: coordinate.longitude,
            lat2: nearest.latitude,
            lon2: nearest.longitude
        )

        // Keep original result if dataset match is too far from tapped point.
        guard nearestDistance <= 80 else { return nil }
        return explorerCity(from: nearest, region: city.region)
    }

    private func explorerCity(from localCity: LocalCityCenter, region: String?) -> ExplorerCity {
        ExplorerCity(
            name: localCity.name,
            country: Self.countryNameByCode[localCity.countryCode] ?? localCity.countryCode,
            region: region,
            latitude: localCity.latitude,
            longitude: localCity.longitude
        )
    }

    private func countryCode(forCountryName country: String) -> String? {
        Self.countryCodeByNormalizedName[Self.normalize(country)]
    }

    private static func loadLocalCityCenters() -> [LocalCityCenter] {
        var bestByKey: [String: LocalCityCenter] = [:]

        for entry in CityDataset.populatedPlaces {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let countryCode = entry.countryCode
            guard !name.isEmpty, countryCode.count == 2 else { continue }

            let population = entry.population
            guard population >= 15_000 else { continue }

            let key = cityKey(name: name, countryCode: countryCode)
            if let existing = bestByKey[key], existing.population >= population {
                continue
            }

            bestByKey[key] = LocalCityCenter(
                name: name,
                countryCode: countryCode,
                latitude: entry.latitude,
                longitude: entry.longitude,
                population: population
            )
        }

        return bestByKey.values
            .sorted { lhs, rhs in
                if lhs.population == rhs.population {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.population > rhs.population
            }
            .prefix(12_000)
            .map { $0 }
    }

    private static func cityKey(name: String, countryCode: String) -> String {
        "\(normalize(name))|\(countryCode.uppercased())"
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .lowercased()
    }

    private func haversineDistanceKm(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(p1) * cos(p2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }
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
    let description: String?
    let extract: String
    let thumbnail: Thumbnail?
    let contentURLs: ContentURLs?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case extract
        case thumbnail
        case contentURLs = "content_urls"
    }
}

private struct GeoapifyPlacesResponse: Decodable {
    struct Feature: Decodable {
        struct Geometry: Decodable {
            let coordinates: [Double]
        }

        struct Properties: Decodable {
            let name: String?
            let categories: [String]?
            let formatted: String?
        }

        let geometry: Geometry
        let properties: Properties
    }

    let features: [Feature]
}

private struct GoogleTextSearchRequest: Encodable {
    let textQuery: String
    let maxResultCount: Int?
    let languageCode: String?
    let locationBias: GoogleLocationBias?
    let includedType: String?
    let strictTypeFiltering: Bool?
}

private struct GoogleLocationBias: Encodable {
    let circle: GoogleCircle?
}

private struct GoogleCircle: Encodable {
    let center: GoogleLatLng
    let radius: Double
}

private struct GoogleLatLng: Encodable {
    let latitude: Double
    let longitude: Double
}

private struct GoogleTextSearchResponse: Decodable {
    let places: [GooglePlaceResult]?
}

private struct GooglePlaceResult: Decodable {
    struct DisplayName: Decodable {
        let text: String?
    }

    struct Location: Decodable {
        let latitude: Double
        let longitude: Double
    }

    struct AddressComponent: Decodable {
        let longText: String?
        let shortText: String?
        let types: [String]?
    }

    struct OpeningHours: Decodable {
        let openNow: Bool?

        enum CodingKeys: String, CodingKey {
            case openNow = "openNow"
        }
    }

    let id: String?
    let displayName: DisplayName?
    let formattedAddress: String?
    let location: Location?
    let googleMapsUri: String?
    let types: [String]?
    let addressComponents: [AddressComponent]?
    let rating: Double?
    let userRatingCount: Int?
    let priceLevel: Int?
    let currentOpeningHours: OpeningHours?
    let primaryTypeDisplayName: DisplayName?
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

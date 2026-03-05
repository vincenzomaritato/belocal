import Foundation

enum CodableStorage {
    static func encode<T: Encodable>(_ value: T, fallback: String = "") -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return json
    }

    static func decode<T: Decodable>(_ json: String, as type: T.Type, fallback: T) -> T {
        guard let data = json.data(using: .utf8) else {
            return fallback
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode(T.self, from: data)) ?? fallback
    }
}

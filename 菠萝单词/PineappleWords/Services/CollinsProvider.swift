import Foundation

struct CollinsEntry: Sendable {
    var headword: String
    var definitions: [String]
    var attribution: String
}
protocol CollinsProviding: Sendable {
    func lookup(_ word: String) async throws -> CollinsEntry
}
enum CollinsRegistry {
    // TODO: Supply a licensed Collins adapter after the API contract and credentials are provided.
    // No unauthorised scraping, invented dictionary data, or dependency from the local learning core.
    static let provider: (any CollinsProviding)? = nil
    static var isConfigured: Bool { provider != nil }
}

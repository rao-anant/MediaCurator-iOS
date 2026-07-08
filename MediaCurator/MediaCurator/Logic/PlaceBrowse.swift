import Foundation

/// A photo's place split into browseable levels; blank fields where unknown.
struct PlaceRecord: Equatable {
    let city: String
    let state: String
    let country: String
}

/// A place bucket at some level (country / state / city) with its photo count.
struct PlaceCount: Equatable, Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

/// How to order a browse list.
enum PlaceSort { case count, name }

/// Pure aggregation of per-photo `PlaceRecord`s into ranked browseable lists (spec §7).
/// Powers browse **A** (flat cities) and **B** (country → state → city drill-down).
/// Mirrors the Android `PlaceBrowse`; JVM/Swift unit-tested.
enum PlaceBrowse {

    private static func rank(_ names: [String], _ sort: PlaceSort) -> [PlaceCount] {
        var counts: [String: Int] = [:]
        for n in names where !n.isEmpty { counts[n, default: 0] += 1 }
        let items = counts.map { PlaceCount(name: $0.key, count: $0.value) }
        switch sort {
        case .count:
            return items.sorted { a, b in a.count != b.count ? a.count > b.count : a.name < b.name }
        case .name:
            return items.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    /// Option A: every distinct city.
    static func cities(_ records: [PlaceRecord], sort: PlaceSort = .count) -> [PlaceCount] {
        rank(records.map { $0.city }, sort)
    }

    /// Level 1: distinct countries.
    static func countries(_ records: [PlaceRecord], sort: PlaceSort = .count) -> [PlaceCount] {
        rank(records.map { $0.country }, sort)
    }

    /// Level 2: states within `country`.
    static func states(_ records: [PlaceRecord], country: String, sort: PlaceSort = .count) -> [PlaceCount] {
        rank(records.filter { $0.country == country }.map { $0.state }, sort)
    }

    /// Level 3: cities within `country`/`state`.
    static func citiesIn(_ records: [PlaceRecord], country: String, state: String, sort: PlaceSort = .count) -> [PlaceCount] {
        rank(records.filter { $0.country == country && $0.state == state }.map { $0.city }, sort)
    }

    /// All cities in `country` regardless of state — for city-states with no state level.
    static func citiesInCountry(_ records: [PlaceRecord], country: String, sort: PlaceSort = .count) -> [PlaceCount] {
        rank(records.filter { $0.country == country }.map { $0.city }, sort)
    }
}

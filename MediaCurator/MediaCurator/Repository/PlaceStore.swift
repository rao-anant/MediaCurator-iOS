import Foundation

/// Persistent cache of each photo's reverse-geocoded place (spec §7 v1.1). Mirrors the Android
/// `PlaceStore`. Keyed by PHAsset localIdentifier → (size, value), where value is
/// `city|state|country|alias1,alias2` (or **empty** = scanned but no GPS, so it isn't re-read).
/// Persisted to Application Support as `id \t size \t value` lines.
///
/// NOTE: the Android reinstall-survival mirror (Downloads, remapped by displayName+size) is not
/// yet ported — on iOS that maps to iCloud/Documents; deferred. A reinstall re-EXIF-scans for now.
actor PlaceStore {

    static let shared = PlaceStore()
    private init() {}

    private var cache: [String: (size: Int64, value: String)] = [:]
    private var loaded = false

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("place_cache_v2.txt")
    }

    func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let p = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 2, let size = Int64(p[1]) else { continue }
            cache[p[0]] = (size, p.count >= 3 ? p[2] : "")
        }
    }

    func hasEntry(id: String, size: Int64) -> Bool { cache[id]?.size == size }

    func save(id: String, size: Int64, city: GeoCity?) {
        cache[id] = (size, Self.encode(city))
    }

    /// Count of photos that resolved to a place (excludes "no GPS" markers).
    func locatedCount() -> Int { cache.values.filter { !$0.value.isEmpty }.count }

    var isEmpty: Bool { cache.isEmpty }

    /// One `PlaceRecord` per located photo — input for `PlaceBrowse`. Pass live ids to exclude
    /// stale entries for deleted photos so counts match what a tap returns.
    func records(validIDs: Set<String>? = nil) -> [PlaceRecord] {
        cache.compactMap { id, entry in
            if let validIDs, !validIDs.contains(id) { return nil }
            return entry.value.isEmpty ? nil : Self.decode(entry.value)
        }
    }

    /// localIdentifier → search tokens (city, aliases, state, country); located photos only.
    func searchIndex() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (id, entry) in cache where !entry.value.isEmpty { out[id] = Self.searchTokens(entry.value) }
        return out
    }

    func flush() {
        var text = ""
        for (id, entry) in cache { text += "\(id)\t\(entry.size)\t\(entry.value)\n" }
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func clear() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - value codec: "city|state|country|alias1,alias2"

    private static func encode(_ city: GeoCity?) -> String {
        guard let city else { return "" }
        func clean(_ v: String) -> String {
            v.replacingOccurrences(of: "|", with: " ")
             .replacingOccurrences(of: "\t", with: " ")
             .trimmingCharacters(in: .whitespaces)
        }
        let aliases = city.altNames.map { clean($0.replacingOccurrences(of: ",", with: " ")) }.joined(separator: ",")
        return "\(clean(city.name))|\(clean(city.admin1))|\(clean(city.country))|\(aliases)"
    }

    private static func decode(_ value: String) -> PlaceRecord? {
        let p = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let first = p.first, !first.isEmpty else { return nil }
        return PlaceRecord(city: p[0], state: p.count > 1 ? p[1] : "", country: p.count > 2 ? p[2] : "")
    }

    private static func searchTokens(_ value: String) -> [String] {
        let p = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let city = p.count > 0 ? p[0] : ""
        let state = p.count > 1 ? p[1] : ""
        let country = p.count > 2 ? p[2] : ""
        let aliases = p.count > 3 ? p[3].split(separator: ",").map(String.init) : []
        var out = [city] + aliases + [state, country]
        out = out.filter { !$0.isEmpty }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}

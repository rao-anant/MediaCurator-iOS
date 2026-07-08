import Foundation

/// Offline reverse-geocoding for **Place search** (spec §7 v1.1). Pure and platform-independent —
/// a verbatim mirror of the Android `GeoIndex.kt` (see docs/FUNCTIONAL_SPEC §7). No network: the
/// OS geocoders (`CLGeocoder`, `android.location.Geocoder`) are network-backed and would break the
/// "no internet, ever" promise.
///
/// Nearest-neighbour runs in **3-D on the unit sphere** (each city → x,y,z), so Euclidean chord
/// distance is monotonic with great-circle distance — correct across the antimeridian and poles,
/// which a naïve 2-D lat/lon tree gets wrong.
struct GeoCity: Equatable {
    let name: String
    let altNames: [String]
    let lat: Double
    let lon: Double
    let country: String
    let admin1: String

    /// Tokens worth indexing for search (city, aliases, state, country).
    var searchNames: [String] {
        var out = [name] + altNames
        if !admin1.isEmpty { out.append(admin1) }
        if !country.isEmpty { out.append(country) }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// e.g. "Bengaluru, Karnataka" — for display.
    var label: String { admin1.isEmpty ? name : "\(name), \(admin1)" }
}

final class GeoIndex {
    private let cities: [GeoCity]
    private let pts: [[Double]]          // each city on the unit sphere, in lockstep with `cities`
    private let root: Node?

    var size: Int { cities.count }

    private final class Node {
        let idx: Int
        let axis: Int
        var left: Node?
        var right: Node?
        init(idx: Int, axis: Int) { self.idx = idx; self.axis = axis }
    }

    init(cities: [GeoCity]) {
        self.cities = cities
        self.pts = cities.map { GeoIndex.toXyz(lat: $0.lat, lon: $0.lon) }
        self.root = GeoIndex.build(Array(cities.indices), depth: 0, pts: pts)
    }

    private static func build(_ idxs: [Int], depth: Int, pts: [[Double]]) -> Node? {
        if idxs.isEmpty { return nil }
        let axis = depth % 3
        let sorted = idxs.sorted { pts[$0][axis] < pts[$1][axis] }
        let mid = sorted.count / 2
        let node = Node(idx: sorted[mid], axis: axis)
        node.left  = build(Array(sorted[0..<mid]), depth: depth + 1, pts: pts)
        node.right = build(Array(sorted[(mid + 1)...]), depth: depth + 1, pts: pts)
        return node
    }

    /// The city nearest to (lat, lon), or nil if the dataset is empty.
    func nearest(lat: Double, lon: Double) -> GeoCity? {
        guard let start = root else { return nil }
        let target = GeoIndex.toXyz(lat: lat, lon: lon)
        var bestIdx = start.idx
        var bestDist = GeoIndex.dist2(pts[start.idx], target)

        func search(_ node: Node?) {
            guard let node else { return }
            let d = GeoIndex.dist2(pts[node.idx], target)
            if d < bestDist { bestDist = d; bestIdx = node.idx }
            let diff = target[node.axis] - pts[node.idx][node.axis]
            let near = diff < 0 ? node.left : node.right
            let far  = diff < 0 ? node.right : node.left
            search(near)
            // Only cross the splitting plane if a closer point could live on the far side.
            if diff * diff < bestDist { search(far) }
        }
        search(start)
        return cities[bestIdx]
    }

    // MARK: - Parsing

    /// Build from trimmed `name|alt,alt|lat|lon|country|admin` lines (blank/`#` skipped).
    static func fromLines<S: Sequence>(_ lines: S) -> GeoIndex where S.Element == String {
        GeoIndex(cities: lines.compactMap { parseLine($0) })
    }

    /// Parse one trimmed dataset line; nil if malformed.
    static func parseLine(_ line: String) -> GeoCity? {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s.hasPrefix("#") { return nil }
        let p = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if p.count < 4 { return nil }
        guard let lat = Double(p[2]), let lon = Double(p[3]) else { return nil }
        let alts = p[1].isEmpty ? []
            : p[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return GeoCity(
            name: p[0].trimmingCharacters(in: .whitespaces),
            altNames: alts,
            lat: lat,
            lon: lon,
            country: (p.count > 4 ? p[4] : "").trimmingCharacters(in: .whitespaces),
            admin1: (p.count > 5 ? p[5] : "").trimmingCharacters(in: .whitespaces)
        )
    }

    // MARK: - Geometry

    private static func toXyz(lat: Double, lon: Double) -> [Double] {
        let latR = lat * .pi / 180
        let lonR = lon * .pi / 180
        let cl = cos(latR)
        return [cl * cos(lonR), cl * sin(lonR), sin(latR)]
    }

    private static func dist2(_ a: [Double], _ b: [Double]) -> Double {
        let dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2]
        return dx * dx + dy * dy + dz * dz
    }
}

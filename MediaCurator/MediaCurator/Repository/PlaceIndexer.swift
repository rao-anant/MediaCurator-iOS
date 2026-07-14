import Foundation
import Photos
import CoreLocation

/// Background reverse-geocoding indexer (spec §7 v1.1). Reads each photo's `PHAsset.location`,
/// maps it to the nearest city via the bundled `GeoIndex`, and records city/state/country in
/// `PlaceStore`. Fully offline. Mirrors the Android `PlaceIndexer`.
actor PlaceIndexer {

    static let shared = PlaceIndexer()
    private init() {}

    private var geo: GeoIndex? = nil
    private var indexing = false

    /// Load the bundled GeoNames dataset once (~235k cities → k-d tree).
    private func loadGeoIfNeeded() -> GeoIndex? {
        if let geo { return geo }
        guard let url = Bundle.main.url(forResource: "geo_cities", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let index = GeoIndex.fromLines(text.split(separator: "\n").lazy.map(String.init))
        geo = index
        return index
    }

    /// Index any not-yet-scanned photos. `progress` is called on the main actor with (done, total).
    /// Returns the number of located photos after the run.
    @discardableResult
    func index(_ items: [MediaItem], progress: @MainActor @Sendable @escaping (Int, Int) -> Void) async -> Int {
        guard !indexing else { return await PlaceStore.shared.locatedCount() }
        indexing = true
        defer { indexing = false }

        await PlaceStore.shared.ensureLoaded()
        guard let geo = loadGeoIfNeeded() else { return 0 }

        // Only photos we haven't scanned yet (id+size) — filtered in one actor hop.
        let images = items.filter { $0.type == .image }
        let todo = await PlaceStore.shared.pending(images)
        let total = todo.count
        guard total > 0 else { return await PlaceStore.shared.locatedCount() }

        // Read every asset's GPS location in ONE Photos fetch instead of one fetch per photo —
        // by far the dominant cost for a large library.
        let locations = Self.locations(for: todo.map(\.localIdentifier))

        var done = 0
        for item in todo {
            if Task.isCancelled { break }
            let city = locations[item.localIdentifier].map { loc in
                geo.nearest(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
            } ?? nil
            await PlaceStore.shared.save(id: item.id, size: item.size, city: city)
            done += 1
            if done % 50 == 0 { await PlaceStore.shared.flush() }
            // Throttle progress UI updates (every 25) — no main-actor hop per item.
            if done % 25 == 0 || done == total {
                let d = done
                await MainActor.run { progress(d, total) }
            }
        }
        await PlaceStore.shared.flush()
        return await PlaceStore.shared.locatedCount()
    }

    /// GPS locations for many assets in a single Photos fetch (no-GPS / missing assets are simply
    /// absent from the map). `PHAsset.location` needs no extra permission (spec §7 iOS note).
    private static func locations(for ids: [String]) -> [String: CLLocation] {
        guard !ids.isEmpty else { return [:] }
        var out: [String: CLLocation] = [:]
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        result.enumerateObjects { asset, _, _ in
            if let loc = asset.location { out[asset.localIdentifier] = loc }
        }
        return out
    }
}

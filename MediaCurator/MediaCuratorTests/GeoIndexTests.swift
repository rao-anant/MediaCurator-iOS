import Testing
import Foundation
@testable import MediaCurator

/// Mirrors the Android GeoIndex tests: parsing + nearest-city (incl. antimeridian/pole cases the
/// 3-D unit-sphere tree is built to get right).
struct GeoIndexTests {

    @Test func parseValidLine() {
        let c = GeoIndex.parseLine("Bengaluru|Bangalore,Bengaluru|12.97194|77.59369|India|Karnataka")
        #expect(c != nil)
        #expect(c?.name == "Bengaluru")
        #expect(c?.altNames == ["Bangalore", "Bengaluru"])
        #expect(c?.country == "India")
        #expect(c?.admin1 == "Karnataka")
        #expect(c?.label == "Bengaluru, Karnataka")
        #expect(c?.searchNames.contains("Bangalore") == true)
        #expect(c?.searchNames.contains("India") == true)
    }

    @Test func parseMalformed() {
        #expect(GeoIndex.parseLine("") == nil)
        #expect(GeoIndex.parseLine("# comment") == nil)
        #expect(GeoIndex.parseLine("OnlyName|alt") == nil)          // too few fields
        #expect(GeoIndex.parseLine("Name||notlat|notlon") == nil)   // bad coords
    }

    @Test func nearestPicksClosestCity() {
        let index = GeoIndex(cities: [
            GeoCity(name: "London", altNames: [], lat: 51.5074, lon: -0.1278, country: "United Kingdom", admin1: "England"),
            GeoCity(name: "Paris",  altNames: [], lat: 48.8566, lon: 2.3522,  country: "France", admin1: "Île-de-France"),
            GeoCity(name: "Tokyo",  altNames: [], lat: 35.6762, lon: 139.6503, country: "Japan", admin1: "Tokyo"),
        ])
        // A point just outside London → London.
        #expect(index.nearest(lat: 51.6, lon: -0.2)?.name == "London")
        // A point near Paris → Paris.
        #expect(index.nearest(lat: 48.9, lon: 2.3)?.name == "Paris")
    }

    @Test func nearestAcrossAntimeridian() {
        // Two cities straddling the antimeridian (lon +179 vs -179): a 2-D lon tree would treat
        // them as ~358° apart; on the unit sphere they're neighbours.
        let index = GeoIndex(cities: [
            GeoCity(name: "EastSide", altNames: [], lat: 0, lon: 179.0, country: "", admin1: ""),
            GeoCity(name: "WestSide", altNames: [], lat: 0, lon: -179.0, country: "", admin1: ""),
        ])
        // A point at lon -179.5 is closest to WestSide but very near EastSide too; at lon 179.9
        // the nearest must be EastSide (chord distance, not raw lon delta).
        #expect(index.nearest(lat: 0, lon: 179.9)?.name == "EastSide")
        #expect(index.nearest(lat: 0, lon: -179.9)?.name == "WestSide")
    }

    @Test func emptyIndexReturnsNil() {
        #expect(GeoIndex(cities: []).nearest(lat: 0, lon: 0) == nil)
    }
}

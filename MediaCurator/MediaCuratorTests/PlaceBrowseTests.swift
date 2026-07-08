import Testing
@testable import MediaCurator

/// Mirrors the Android PlaceBrowse aggregation tests.
struct PlaceBrowseTests {

    private let records = [
        PlaceRecord(city: "Bengaluru", state: "Karnataka", country: "India"),
        PlaceRecord(city: "Bengaluru", state: "Karnataka", country: "India"),
        PlaceRecord(city: "Mumbai",    state: "Maharashtra", country: "India"),
        PlaceRecord(city: "Munich",    state: "Bavaria", country: "Germany"),
        PlaceRecord(city: "Singapore", state: "", country: "Singapore"),
    ]

    @Test func citiesRankedByCount() {
        let cities = PlaceBrowse.cities(records, sort: .count)
        #expect(cities.first?.name == "Bengaluru")
        #expect(cities.first?.count == 2)
    }

    @Test func citiesByName() {
        let cities = PlaceBrowse.cities(records, sort: .name)
        #expect(cities.map { $0.name } == ["Bengaluru", "Mumbai", "Munich", "Singapore"])
    }

    @Test func countriesAggregate() {
        let countries = PlaceBrowse.countries(records, sort: .count)
        #expect(countries.first?.name == "India")
        #expect(countries.first?.count == 3)
    }

    @Test func statesWithinCountry() {
        let states = PlaceBrowse.states(records, country: "India", sort: .count)
        #expect(states.map { $0.name }.sorted() == ["Karnataka", "Maharashtra"])
        #expect(states.first { $0.name == "Karnataka" }?.count == 2)
    }

    @Test func citiesWithinState() {
        let cities = PlaceBrowse.citiesIn(records, country: "India", state: "Karnataka")
        #expect(cities.count == 1)
        #expect(cities.first?.name == "Bengaluru")
        #expect(cities.first?.count == 2)
    }

    @Test func cityStateShowsCitiesUnderCountry() {
        // Singapore has no state level — citiesInCountry surfaces the city directly.
        let cities = PlaceBrowse.citiesInCountry(records, country: "Singapore")
        #expect(cities.map { $0.name } == ["Singapore"])
    }
}

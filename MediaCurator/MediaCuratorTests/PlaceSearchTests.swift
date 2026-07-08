import Testing
@testable import MediaCurator

/// Place-search normalization + matching (spec §7): diacritics, Turkish İ, aliases, typos.
struct PlaceSearchTests {

    @Test func normalizeFoldsDiacritics() {
        #expect(PlaceSearch.normalize("München") == "munchen")
        #expect(PlaceSearch.normalize("São Paulo") == "sao paulo")
        #expect(PlaceSearch.normalize("İmrahor") == "imrahor")
    }

    @Test func matchesSubstringCaseAndDiacriticInsensitive() {
        #expect(PlaceSearch.matches(query: "munich", token: "Munich"))
        #expect(PlaceSearch.matches(query: "munch", token: "München"))
        #expect(PlaceSearch.matches(query: "PARIS", token: "Paris"))
    }

    @Test func matchesTypoWithinOneEdit() {
        #expect(PlaceSearch.matches(query: "pari",  token: "Paris"))   // missing letter
        #expect(PlaceSearch.matches(query: "loncon", token: "London")) // one substitution
        #expect(!PlaceSearch.matches(query: "xyzzy", token: "London"))
    }

    @Test func matchesAnyAcrossTokens() {
        let tokens = ["Mumbai", "Bombay", "Maharashtra", "India"]
        #expect(PlaceSearch.matchesAny(query: "bombay", tokens: tokens))   // alias
        #expect(PlaceSearch.matchesAny(query: "india", tokens: tokens))    // country
        #expect(PlaceSearch.matchesAny(query: "maharashtra", tokens: tokens))
        #expect(!PlaceSearch.matchesAny(query: "tokyo", tokens: tokens))
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(PlaceSearch.matchesAny(query: "", tokens: ["Anything"]))
    }
}

import Foundation

/// Diacritic-normalized, typo-tolerant place matching (spec §7). Pure/testable — mirrors the
/// Android place-search normalization ("München" → "munchen", Turkish "İmrahor" → "imrahor").
enum PlaceSearch {

    /// Fold diacritics + lowercase, with an explicit Turkish dotted-İ fix (folding maps it to "i̇").
    static func normalize(_ s: String) -> String {
        let turkishFixed = s.replacingOccurrences(of: "İ", with: "I")
                            .replacingOccurrences(of: "ı", with: "i")
        return turkishFixed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    /// True if `query` matches `token` — normalized prefix/substring, or (for short-ish tokens)
    /// within edit distance 1 to tolerate a typo.
    static func matches(query: String, token: String) -> Bool {
        let q = normalize(query)
        if q.isEmpty { return true }
        let t = normalize(token)
        if t.contains(q) { return true }
        // Typo tolerance: allow one edit when the query is a near-length match of the token.
        if abs(t.count - q.count) <= 1 && editDistance(q, t) <= 1 { return true }
        return false
    }

    /// True if any of a place's tokens (city, aliases, state, country) matches the query.
    static func matchesAny(query: String, tokens: [String]) -> Bool {
        let q = normalize(query)
        if q.isEmpty { return true }
        return tokens.contains { matches(query: q, token: $0) }
    }

    /// Classic Levenshtein distance (capped small use — place tokens are short).
    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}

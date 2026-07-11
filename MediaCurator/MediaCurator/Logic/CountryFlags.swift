import Foundation

/// Maps country names → flag emoji using the bundled `country_codes.tsv` (name<TAB>ISO2).
/// Mirrors the Android place-browse flags. (Flag emoji render on device; the simulator font
/// may show them as tofu.)
enum CountryFlags {
    private static let nameToCode: [String: String] = {
        guard let url = Bundle.main.url(forResource: "country_codes", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let p = line.split(separator: "\t").map(String.init)
            if p.count >= 2 { map[p[0]] = p[1].uppercased() }
        }
        return map
    }()

    /// Flag emoji for a country name, or a globe if unknown.
    static func flag(for country: String) -> String {
        guard let code = nameToCode[country], code.count == 2 else { return "🌐" }
        let base: UInt32 = 0x1F1E6 - 0x41   // regional indicator 'A' offset
        var s = ""
        for u in code.unicodeScalars {
            if let scalar = UnicodeScalar(base + u.value) { s.unicodeScalars.append(scalar) }
        }
        return s.isEmpty ? "🌐" : s
    }
}

/// Deterministic colorful chip background per place name (cities repeat colors — that's fine,
/// it just reads as varied; matches Android's by-city look).
enum ChipPalette {
    // Deep, saturated tones (white text reads cleanly on all of them).
    static let colors: [(r: Double, g: Double, b: Double)] = [
        (0.13, 0.27, 0.60), (0.70, 0.14, 0.28), (0.36, 0.18, 0.58), (0.09, 0.42, 0.38),
        (0.72, 0.42, 0.06), (0.15, 0.35, 0.62), (0.22, 0.44, 0.19), (0.42, 0.27, 0.20),
        (0.62, 0.22, 0.15), (0.11, 0.44, 0.46), (0.44, 0.19, 0.44), (0.22, 0.28, 0.54),
    ]

    static func color(for name: String) -> (Double, Double, Double) {
        var h = 5381
        for b in name.utf8 { h = ((h << 5) &+ h) &+ Int(b) }
        return colors[abs(h) % colors.count]
    }
}

import Foundation

/// Shared formatting helpers. Mirrors static methods in Android's `GalleryAdapter`.
enum Formatters {

    /// "1.4 GB", "230 MB", "512 KB", "44 B"
    static func bytes(_ n: Int64) -> String {
        let abs = n < 0 ? 0 : n
        switch abs {
        case 0..<1_024:
            return "\(abs) B"
        case 1_024..<1_048_576:
            return String(format: "%.0f KB", Double(abs) / 1_024)
        case 1_048_576..<1_073_741_824:
            return String(format: "%.1f MB", Double(abs) / 1_048_576)
        default:
            return String(format: "%.2f GB", Double(abs) / 1_073_741_824)
        }
    }

    /// Short count: 1 234 → "1.2K", 1 234 567 → "1.2M", else plain number
    static func countShort(_ n: Int) -> String {
        switch n {
        case 0..<1_000:   return "\(n)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000)
        default:          return String(format: "%.1fM", Double(n) / 1_000_000)
        }
    }

    /// "YYYY-MM" → "March 2024"
    static func monthLabel(from key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year  = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month)
        else { return key }
        let names = ["January","February","March","April","May","June",
                     "July","August","September","October","November","December"]
        return "\(names[month - 1]) \(year)"
    }

    /// "YYYY-MM" → "Mar 2024". Short form for tight status rows (e.g. the "Came from" label
    /// beside the sort order), matching Android's copy exactly.
    static func monthLabelShort(from key: String) -> String {
        let full = monthLabel(from: key)
        guard let space = full.firstIndex(of: " ") else { return full }
        return String(full[full.startIndex..<space].prefix(3)) + full[space...]
    }
}

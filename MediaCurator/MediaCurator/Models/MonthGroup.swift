import Foundation

/// A calendar month bucket containing media items.
/// Mirrors Android's `MonthGroup` data class.
struct MonthGroup: Identifiable {
    let year: Int
    let month: Int  // 1-based
    var items: [MediaItem]

    /// "YYYY-MM" key, e.g. "2024-03"
    var key: String { PreferencesManager.monthKey(year: year, month: month) }

    /// "March 2024"
    var label: String {
        let components = DateComponents(year: year, month: month)
        let date = Calendar.current.date(from: components) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date)
    }

    var id: String { key }
}

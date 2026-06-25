import Foundation

enum SortMode: String, Codable, CaseIterable {
    case dateNewest       = "DATE_NEWEST"
    case dateOldest       = "DATE_OLDEST"
    case sizeAbsolute     = "SIZE_ABSOLUTE"
    case sizeWithinMonth  = "SIZE_WITHIN_MONTH"
    case countPerMonth    = "COUNT_PER_MONTH"
}

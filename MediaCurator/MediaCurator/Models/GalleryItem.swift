import Foundation

/// Flat list element for the gallery RecyclerView equivalent.
/// Mirrors Android's `GalleryItem` sealed class.
///
/// `structuralVersion` is bumped whenever the list shape changes (sort, expand/collapse)
/// so the SwiftUI List can detect when it needs a full redraw vs. incremental diff.
enum GalleryItem: Identifiable {
    case yearHeader(YearHeader)
    case header(Header)
    case subHeader(SubHeader)
    case media(MediaCell)
    case footer(Footer)

    var id: String {
        switch self {
        case .yearHeader(let y):  return "year-\(y.year)"
        case .header(let h):      return "month-\(h.monthKey)"
        case .subHeader(let s):   return "sub-\(s.subKey)"
        case .media(let m):       return "media-\(m.mediaItem.id)"
        case .footer(let f):      return "footer-\(f.monthKey)"
        }
    }

    var structuralVersion: Int {
        switch self {
        case .yearHeader(let y):  return y.structuralVersion
        case .header(let h):      return h.structuralVersion
        case .subHeader(let s):   return s.structuralVersion
        case .media(let m):       return m.structuralVersion
        case .footer(let f):      return f.structuralVersion
        }
    }

    /// The month this row belongs to (nil for year headers) — used to measure a month's
    /// rendered length for the walk gate.
    var monthKey: String? {
        switch self {
        case .yearHeader:         return nil
        case .header(let h):      return h.monthKey
        case .subHeader(let s):   return s.monthKey
        case .media(let m):       return m.monthKey
        case .footer(let f):      return f.monthKey
        }
    }

    // MARK: - Nested types

    struct YearHeader {
        let year: Int
        let totalItems: Int
        let totalBytes: Int64
        let isExpanded: Bool
        let photoCount: Int
        let videoCount: Int
        let pdfCount: Int
        let audioCount: Int
        let previewIdentifiers: [String]  // PHAsset localIdentifiers for thumbnail strip
        let curatedPct: Int               // 0-100, % of months hidden
        let structuralVersion: Int
    }

    struct Header {
        let monthKey: String
        let label: String
        let count: Int
        let totalBytes: Int64
        let isExpanded: Bool
        let photoCount: Int
        let videoCount: Int
        let pdfCount: Int
        let audioCount: Int
        let structuralVersion: Int
    }

    struct SubHeader {
        let subKey: String      // e.g. "2024-03:cam" or "2024-03:wa"
        let monthKey: String
        let label: String       // "Camera & Others" or "WhatsApp"
        let count: Int
        let totalBytes: Int64
        let isExpanded: Bool
        let photoCount: Int
        let videoCount: Int
        let pdfCount: Int
        let audioCount: Int
        let structuralVersion: Int
    }

    struct MediaCell {
        let mediaItem: MediaItem
        let monthKey: String
        let indexInMonth: Int
        /// Non-nil only in SIZE_ABSOLUTE flat mode — date badge shown on thumbnail.
        let dateLabel: String?
        let structuralVersion: Int
    }

    struct Footer {
        let monthKey: String
        let structuralVersion: Int
    }
}

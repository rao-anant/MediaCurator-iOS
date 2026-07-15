import SwiftUI

/// Year header row — tap to expand/collapse the year.
struct YearHeaderRow: View {
    let header: GalleryItem.YearHeader
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: header.isExpanded ? "chevron.down" : "chevron.right")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(String(header.year))
                .font(.title3).bold()
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.countShort(header.totalItems))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(Formatters.bytes(header.totalBytes))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            if header.curatedPct > 0 {
                Text("\(header.curatedPct)%")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
        // Whole row is the tap target (incl. the leading chevron), like MonthHeaderRow.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Month header row — tap the row to expand/collapse. Hiding a month is done via the
/// "Hide Month from this app" button at the bottom of the expanded month.
struct MonthHeaderRow: View {
    let header: GalleryItem.Header
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: header.isExpanded ? "chevron.down" : "chevron.right")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(header.label).font(.headline)
                typeCountLine
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.countShort(header.count))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(Formatters.bytes(header.totalBytes))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var typeCountLine: some View {
        HStack(spacing: 6) {
            if header.photoCount > 0 { badge("\(header.photoCount)", "photo") }
            if header.videoCount > 0 { badge("\(header.videoCount)", "video") }
            if header.pdfCount   > 0 { badge("\(header.pdfCount)",   "doc.text") }
            if header.audioCount > 0 { badge("\(header.audioCount)", "waveform") }
        }
    }

    private func badge(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

/// WhatsApp / Camera sub-group header.
struct SubHeaderRow: View {
    let sub: GalleryItem.SubHeader
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: sub.isExpanded ? "chevron.down" : "chevron.right")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(sub.label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(Formatters.countShort(sub.count))
                .font(.caption).foregroundStyle(.tertiary)
            Text(Formatters.bytes(sub.totalBytes))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24).padding(.vertical, 6)
        // Whole row is the tap target (incl. the leading chevron), like MonthHeaderRow — a Button
        // label didn't reliably hit-test the thin chevron.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

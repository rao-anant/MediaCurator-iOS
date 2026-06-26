import SwiftUI

/// Shared "Media Stats" dialog (spec §9) — monospace counts/sizes/cleaned-up/in-trash.
/// Audio/PDF rows appear only if any exist. "Visible" = items in non-hidden months.
struct StatsView: View {
    @StateObject private var vm = StatsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    countsSection
                    sizesSection
                    cleanedUpSection
                    trashSection
                    Text("✓ All counts match")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.green)
                }
                .font(.system(.subheadline, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Media Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .onAppear { vm.load() }
    }

    // MARK: - Sections

    private var countsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            header("COUNTS", "vis", "hid", "total")
            row("Photos", vis: vm.stats.visiblePhotos, hid: vm.stats.hiddenPhotos, total: vm.stats.totalPhotos)
            row("Videos", vis: vm.stats.visibleVideos, hid: vm.stats.hiddenVideos, total: vm.stats.totalVideos)
            if vm.stats.totalAudios > 0 {
                row("Audio", vis: vm.stats.visibleAudios, hid: vm.stats.hiddenAudios, total: vm.stats.totalAudios)
            }
            if vm.stats.totalPdfs > 0 {
                row("PDFs", vis: vm.stats.visiblePdfs, hid: vm.stats.hiddenPdfs, total: vm.stats.totalPdfs)
            }
            Divider()
            row("All",
                vis: vm.stats.visiblePhotos + vm.stats.visibleVideos + vm.stats.visiblePdfs + vm.stats.visibleAudios,
                hid: vm.stats.hiddenPhotos + vm.stats.hiddenVideos + vm.stats.hiddenPdfs + vm.stats.hiddenAudios,
                total: vm.stats.totalPhotos + vm.stats.totalVideos + vm.stats.totalPdfs + vm.stats.totalAudios)
        }
    }

    private var sizesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            header("SIZES", "vis", "hid", "total")
            sizeRow("Photos", vis: vm.stats.visiblePhotoBytes, hid: vm.stats.hiddenPhotoBytes)
            sizeRow("Videos", vis: vm.stats.visibleVideoBytes, hid: vm.stats.hiddenVideoBytes)
            if vm.stats.totalAudios > 0 {
                sizeRow("Audio", vis: vm.stats.visibleAudioBytes, hid: vm.stats.hiddenAudioBytes)
            }
            if vm.stats.totalPdfs > 0 {
                sizeRow("PDFs", vis: vm.stats.visiblePdfBytes, hid: vm.stats.hiddenPdfBytes)
            }
            Divider()
            let vB = vm.stats.visiblePhotoBytes + vm.stats.visibleVideoBytes + vm.stats.visiblePdfBytes + vm.stats.visibleAudioBytes
            let hB = vm.stats.hiddenPhotoBytes + vm.stats.hiddenVideoBytes + vm.stats.hiddenPdfBytes + vm.stats.hiddenAudioBytes
            sizeRow("All", vis: vB, hid: hB)
        }
    }

    private var cleanedUpSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CLEANED UP (lifetime)").foregroundStyle(.secondary)
            Text("  \(vm.cleanedUpCount) items · \(Formatters.bytes(vm.cleanedUpBytes)) freed")
        }
    }

    private var trashSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("IN TRASH (recoverable)").foregroundStyle(.secondary)
            Text("  \(vm.trashCount) items · \(Formatters.bytes(vm.trashBytes))")
        }
    }

    // MARK: - Row helpers

    private func header(_ title: String, _ a: String, _ b: String, _ c: String) -> some View {
        HStack(spacing: 0) {
            Text(title).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(a).frame(maxWidth: .infinity, alignment: .trailing)
            Text(b).frame(maxWidth: .infinity, alignment: .trailing)
            Text(c).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(.secondary)
    }

    private func row(_ label: String, vis: Int, hid: Int, total: Int) -> some View {
        HStack(spacing: 0) {
            Text(label).frame(width: 90, alignment: .leading)
            Text("\(vis)").frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(hid)").frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(total)").frame(maxWidth: .infinity, alignment: .trailing).bold()
        }
    }

    private func sizeRow(_ label: String, vis: Int64, hid: Int64) -> some View {
        HStack(spacing: 0) {
            Text(label).frame(width: 90, alignment: .leading)
            Text(Formatters.bytes(vis)).frame(maxWidth: .infinity, alignment: .trailing)
            Text(Formatters.bytes(hid)).frame(maxWidth: .infinity, alignment: .trailing)
            Text(Formatters.bytes(vis + hid)).frame(maxWidth: .infinity, alignment: .trailing).bold()
        }
    }
}

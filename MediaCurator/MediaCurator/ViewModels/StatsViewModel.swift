import Foundation
import Combine

/// Computes the shared Media Stats readout (spec §9): per-type visible/hidden/total counts
/// and sizes, lifetime "cleaned up", and current "in trash". Driven from the shared cache so
/// it's consistent with the gallery.
@MainActor
final class StatsViewModel: ObservableObject {

    @Published var stats: MediaStats = .empty
    @Published var cleanedUpCount: Int = 0
    @Published var cleanedUpBytes: Int64 = 0
    @Published var trashCount: Int = 0
    @Published var trashBytes: Int64 = 0
    @Published var isLoading = false

    private let repo  = MediaRepository()
    private let prefs = PreferencesManager()
    private let deletionStats = DeletionStatsStore()

    func load() {
        Task {
            isLoading = true
            defer { isLoading = false }

            let media = await MediaCache.shared.get(repo: repo)
            let done  = prefs.getDoneMonths()
            let cal   = Calendar.current

            func isHidden(_ item: MediaItem) -> Bool {
                let y = cal.component(.year,  from: item.dateTaken)
                let m = cal.component(.month, from: item.dateTaken)
                return done.contains(PreferencesManager.monthKey(year: y, month: m))
            }
            func tally(_ type: MediaType) -> (vis: Int, hid: Int, vB: Int64, hB: Int64) {
                let items = media.filter { $0.type == type }
                let hid = items.filter(isHidden)
                let vis = items.filter { !isHidden($0) }
                return (vis.count, hid.count,
                        vis.reduce(0) { $0 + $1.size }, hid.reduce(0) { $0 + $1.size })
            }

            let p = tally(.image), v = tally(.video), d = tally(.pdf), a = tally(.audio)
            stats = MediaStats(
                visiblePhotos: p.vis, hiddenPhotos: p.hid, totalPhotos: p.vis + p.hid,
                visibleVideos: v.vis, hiddenVideos: v.hid, totalVideos: v.vis + v.hid,
                visiblePdfs:   d.vis, hiddenPdfs:   d.hid, totalPdfs:   d.vis + d.hid,
                visibleAudios: a.vis, hiddenAudios:  a.hid, totalAudios:  a.vis + a.hid,
                visiblePhotoBytes: p.vB, hiddenPhotoBytes: p.hB,
                visibleVideoBytes: v.vB, hiddenVideoBytes: v.hB,
                visiblePdfBytes:   d.vB, hiddenPdfBytes:   d.hB,
                visibleAudioBytes: a.vB, hiddenAudioBytes:  a.hB
            )

            cleanedUpCount = deletionStats.totalDeleted
            cleanedUpBytes = deletionStats.totalBytesFreed

            let liveIDs = Set(media.map(\.id))
            let staged  = prefs.getStagedForDeletion().intersection(liveIDs)
            let trashItems = media.filter { staged.contains($0.id) }
            trashCount = trashItems.count
            trashBytes = trashItems.reduce(0) { $0 + $1.size }
        }
    }
}

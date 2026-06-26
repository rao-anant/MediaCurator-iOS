import SwiftUI

/// Static "How it works" screen (spec §11).
struct HelpView: View {
    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        .init(icon: "rectangle.grid.2x2", title: "Browse, filter & sort",
              detail: "Your library is grouped by Year and Month. Use the chips to show or hide photos, videos, audio, and PDFs, and the sort bar to reorder."),
        .init(icon: "eye.slash", title: "Hide a month",
              detail: "When you've reviewed a month, hide it from the app to track your progress. It stays in your iPhone's Photos — nothing is deleted."),
        .init(icon: "doc.on.doc", title: "Find duplicates",
              detail: "Detects exact-duplicate photos and videos by content so you can delete extra copies and keep the best one."),
        .init(icon: "magnifyingglass", title: "Search",
              detail: "Search file names and text inside PDFs, all on-device."),
        .init(icon: "trash", title: "Safe deletion",
              detail: "Deletes are staged in the Trash. Nothing leaves your iPhone until you review and confirm the batch."),
        .init(icon: "lock.shield", title: "Private by design",
              detail: "Fully offline. No accounts, no ads, no analytics, no network access."),
    ]

    var body: some View {
        List {
            ForEach(features) { f in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: f.icon)
                        .font(.title2).foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.title).font(.headline)
                        Text(f.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Text("Version \(appVersion)")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("How It Works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

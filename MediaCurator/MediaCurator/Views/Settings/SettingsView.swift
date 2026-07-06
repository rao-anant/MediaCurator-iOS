import SwiftUI
import UniformTypeIdentifiers

/// Settings (spec §10): export/import hidden months, Help.
/// (PDF content-search toggle is Phase 2 — see PORTING_NOTES §12.)
struct SettingsView: View {
    private let prefs = PreferencesManager()

    @State private var importing = false
    @State private var exportURL: URL? = nil
    @State private var toast: String? = nil
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Hidden months") {
                Button("Export hidden months") { exportHiddenMonths() }
                Button("Import hidden months") { importing = true }
            }

            Section {
                NavigationLink("How It Works") { HelpView() }
            }

            Section {
                Button("Reset curation progress", role: .destructive) { showResetConfirm = true }
            } footer: {
                Text("Un-hides every month and clears review/scroll progress. Your photos, sort, and filters are untouched.")
            }

            if let toast {
                Section { Text(toast).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
        }
        .confirmationDialog("Reset curation progress?",
                            isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                prefs.resetCurationProgress()
                show("Curation progress reset — all months are back.")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every hidden month reappears and review/scroll progress is cleared. Photos, sort, and filters are not affected.")
        }
    }

    // MARK: - Export / Import (Android-compatible: {"hiddenMonths": ["YYYY-MM", ...]})

    private func exportHiddenMonths() {
        let months = prefs.getDoneMonths().sorted()
        guard !months.isEmpty else { show("No hidden months to export"); return }
        let payload = ["hiddenMonths": months]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        else { show("Export failed"); return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediacurator_hidden_\(stamp).json")
        do { try data.write(to: url); exportURL = url }
        catch { show("Export failed") }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let imported = obj["hiddenMonths"] as? [String] else {
            show("Import failed — invalid file"); return
        }
        let before = prefs.getDoneMonths()
        let merged = before.union(imported)
        prefs.setDoneMonths(merged)
        let added = merged.count - before.count
        show("Import done — \(added) new months added (\(merged.count) total hidden)")
    }

    private func show(_ msg: String) {
        toast = msg
        Task { try? await Task.sleep(nanoseconds: 4_000_000_000); if toast == msg { toast = nil } }
    }
}

// MARK: - Share sheet

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

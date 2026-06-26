import SwiftUI
import UniformTypeIdentifiers

/// Settings (spec §10): PDF-search toggle, export/import hidden months, Help.
struct SettingsView: View {
    private let prefs = PreferencesManager()

    @State private var pdfContentSearch = true
    @State private var importing = false
    @State private var exportURL: URL? = nil
    @State private var toast: String? = nil

    var body: some View {
        Form {
            Section("Search") {
                Toggle("PDF content search", isOn: $pdfContentSearch)
                    .onChange(of: pdfContentSearch) { v in prefs.setPdfContentSearchEnabled(v) }
                Text("When on, text inside PDFs is indexed on-device for search. (PDF support is not yet available in this build.)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hidden months") {
                Button("Export hidden months") { exportHiddenMonths() }
                Button("Import hidden months") { importing = true }
            }

            Section {
                NavigationLink("How It Works") { HelpView() }
            }

            if let toast {
                Section { Text(toast).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pdfContentSearch = prefs.isPdfContentSearchEnabled() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
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

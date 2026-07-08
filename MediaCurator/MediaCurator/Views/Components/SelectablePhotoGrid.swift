import SwiftUI

/// A reusable photo grid with long-press multi-select and a Share/Delete action bar — the shared
/// "unified action bar" used by Hidden and Place-browse (spec §5 / §7). Tapping outside selection
/// opens the item; delete soft-deletes to the staged Trash.
struct SelectablePhotoGrid: View {
    let items: [MediaItem]
    let onOpen: (MediaItem) -> Void
    /// Called after items are staged for deletion so the parent can refresh its list.
    let onDeleted: () -> Void

    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    private let prefs = PreferencesManager()

    private var selectedItems: [MediaItem] { items.filter { selectedIDs.contains($0.id) } }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(items) { item in
                    MediaThumbnailView(
                        cell: .init(mediaItem: item, monthKey: "", indexInMonth: 0,
                                    dateLabel: nil, structuralVersion: 0),
                        isSelecting: selecting,
                        isSelected: selectedIDs.contains(item.id),
                        onTap: {
                            if selecting { toggle(item.id) } else { onOpen(item) }
                        },
                        onLongPress: {
                            selecting = true
                            selectedIDs.insert(item.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .safeAreaInset(edge: .bottom) {
            if selecting { selectionBar }
        }
        .animation(.spring(duration: 0.3), value: selecting)
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private var selectionBar: some View {
        HStack(spacing: 24) {
            Button { selecting = false; selectedIDs = [] } label: { Text("Cancel") }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(selectedIDs.count) selected").font(.subheadline).bold()
                Text(Formatters.bytes(selectedBytes)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { shareItems(selectedItems) } label: { Image(systemName: "square.and.arrow.up").font(.title3) }
                .disabled(selectedIDs.isEmpty)
            Button(role: .destructive, action: deleteSelected) { Image(systemName: "trash").font(.title3) }
                .disabled(selectedIDs.isEmpty).tint(.red)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func deleteSelected() {
        var staged = prefs.getStagedForDeletion()
        for item in selectedItems { staged.insert(item.id) }
        prefs.setStagedForDeletion(staged)
        selecting = false
        selectedIDs = []
        onDeleted()
    }
}

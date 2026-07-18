import SwiftUI

/// The app-managed trash — review staged items, restore them, or commit the deletion.
struct TrashView: View {

    @StateObject private var vm = TrashViewModel()
    @State private var showingDeleteConfirm = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// Fixed column count (like the gallery) rather than adaptive — adaptive packs many small tiles
    /// on a wide iPad. 3 on iPhone, 5 on iPad => big, legible photos on both.
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: hSizeClass == .regular ? 5 : 3)
    }

    var body: some View {
        Group {
            if vm.items.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.load() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Explainer — iOS reality: staged items aren't deleted until committed.
            Text("These photos are hidden from MediaCurator but still on your iPhone. They're removed only when you delete the batch below.")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            // Grid of large tiles (like the gallery / the Android trash) — the photos are the point,
            // so they get the space; the size rides along as MediaThumbnailView's small badge, and a
            // tap-target restore chip sits in the corner. Adaptive columns => bigger tiles on iPad.
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 2) {
                    ForEach(vm.items) { item in
                        MediaThumbnailView(cell: .init(mediaItem: item, monthKey: "",
                                                       indexInMonth: 0, dateLabel: nil,
                                                       structuralVersion: 0)) {}
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .topTrailing) {
                                Button { vm.restore(item) } label: {
                                    Image(systemName: "arrow.uturn.backward.circle.fill")
                                        .font(.title2)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .padding(5)
                                }
                                .buttonStyle(.plain)
                            }
                    }
                }
                .padding(.horizontal, 2)
            }

            // Commit bar
            VStack(spacing: 8) {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    if vm.isCommitting {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 4)
                    } else {
                        Label("Delete \(vm.items.count) from iPhone · \(Formatters.bytes(vm.totalBytes))",
                              systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(vm.isCommitting)

                Button("Restore All") { vm.restoreAll() }
                    .font(.subheadline)
                    .disabled(vm.isCommitting)
            }
            .padding()
        }
        .confirmationDialog("Delete \(vm.items.count) photos from your iPhone? They'll move to the Photos app's Recently Deleted.",
                            isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete \(vm.items.count) Photos", role: .destructive) {
                Task { await vm.emptyTrash() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash").font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Trash is Empty").font(.title3).bold()
            Text("Photos you delete in this app are staged here for review before they're removed from your iPhone.")
                .multilineTextAlignment(.center)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

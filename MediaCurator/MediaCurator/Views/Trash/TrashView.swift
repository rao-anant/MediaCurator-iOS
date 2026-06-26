import SwiftUI

/// The app-managed trash — review staged items, restore them, or commit the deletion.
struct TrashView: View {

    @StateObject private var vm = TrashViewModel()
    @State private var showingDeleteConfirm = false

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

            List {
                ForEach(vm.items) { item in
                    HStack(spacing: 12) {
                        MediaThumbnailView(cell: .init(mediaItem: item, monthKey: "",
                                                       indexInMonth: 0, dateLabel: nil,
                                                       structuralVersion: 0)) {}
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName).font(.subheadline).lineLimit(1)
                            Text(Formatters.bytes(item.size))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { vm.restore(item) }
                            .font(.subheadline)
                            .buttonStyle(.bordered)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
            .listStyle(.plain)

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
            Text("Photos you delete in the gallery are staged here for review before they're removed from your iPhone.")
                .multilineTextAlignment(.center)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

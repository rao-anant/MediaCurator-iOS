import SwiftUI

/// Exact-duplicate review (spec §6). Each group shows its copies; tap a copy to make it the
/// kept one; the rest are staged for (soft) deletion on Delete.
struct DuplicatesView: View {
    @StateObject private var vm = DuplicatesViewModel()
    @State private var showingConfirm = false

    var body: some View {
        Group {
            if vm.isComputing {
                computing
            } else if vm.groups.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Duplicate Photos & Videos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if vm.groups.isEmpty && !vm.isComputing { vm.compute() } }
    }

    private var content: some View {
        VStack(spacing: 0) {
            List {
                ForEach(vm.groups) { group in
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                                    copyTile(group: group, index: idx, item: item)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("\(group.items.count) copies · \(Formatters.bytes(group.reclaimableBytes)) reclaimable")
                    }
                }
            }
            .listStyle(.insetGrouped)

            if vm.deleteCount > 0 {
                VStack(spacing: 8) {
                    Text("\(vm.deleteCount) to delete · \(Formatters.bytes(vm.reclaimableBytes)) reclaimable")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        showingConfirm = true
                    } label: {
                        Label("Delete \(vm.deleteCount) duplicates", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
            }
        }
        .confirmationDialog("Delete duplicates?",
                            isPresented: $showingConfirm, titleVisibility: .visible) {
            Button("Delete \(vm.deleteCount) Duplicates", role: .destructive) {
                vm.stageDuplicatesForDeletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(vm.deleteCount) files (\(Formatters.bytes(vm.reclaimableBytes))) will move to Trash. The kept copy in each group is not affected.")
        }
    }

    private func copyTile(group: DuplicateGroup, index: Int, item: MediaItem) -> some View {
        let isKeep = index == group.keepIndex
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                MediaThumbnailView(cell: .init(mediaItem: item, monthKey: "", indexInMonth: 0,
                                               dateLabel: nil, structuralVersion: 0)) {
                    vm.setKeep(groupID: group.id, index: index)
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isKeep ? Color.green : Color.red, lineWidth: isKeep ? 2 : 1)
                )
                .opacity(isKeep ? 1 : 0.5)

                Image(systemName: isKeep ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isKeep ? Color.green : Color.red)
                    .background(Circle().fill(.white))
                    .padding(4)
            }
            Text(Formatters.bytes(item.size)).font(.caption2).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { vm.setKeep(groupID: group.id, index: index) }
    }

    private var computing: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let p = vm.progress {
                Text("Hashing \(p.done) / \(p.total)…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal").font(.system(size: 52)).foregroundStyle(.green)
            Text("No Exact Duplicates").font(.title3).bold()
            Text("No exact duplicates found in \(vm.indexedCount) indexed files 🎉")
                .multilineTextAlignment(.center)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

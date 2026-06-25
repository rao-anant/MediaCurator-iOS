import SwiftUI
import Photos

/// Main gallery screen — mirrors Android's `MainActivity` + `GalleryAdapter`.
/// Shows a tree of Year → Month → (Camera / WhatsApp) → thumbnail grid.
struct GalleryView: View {

    @StateObject private var vm = GalleryViewModel()
    var scrollToMonthKey: String? = nil

    @State private var selectedItem: MediaItem? = nil
    @State private var showingPermissionAlert = false

    var body: some View {
        Group {
            switch vm.authorizationStatus {
            case .authorized, .limited:
                galleryContent
            case .denied, .restricted:
                permissionDeniedView
            case .notDetermined:
                Color.clear.onAppear { Task { await vm.requestAuthorization() } }
            @unknown default:
                Color.clear
            }
        }
        .overlay(alignment: .bottom) {
            if let undo = vm.pendingUndo {
                HStack(spacing: 16) {
                    Text(undo.message).font(.subheadline)
                    Button("Undo") { vm.undoDelete() }
                        .font(.subheadline.bold())
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 2)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: vm.pendingUndo)
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { galleryToolbar }
        .onAppear {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            vm.authorizationStatus = status
            if status == .authorized || status == .limited {
                vm.loadMedia(forceRefresh: false)
            }
        }
        .fullScreenCover(item: $selectedItem) { item in
            MediaViewerView(vm: vm, startingID: item.id)
        }
    }

    // MARK: - Gallery content

    private var galleryContent: some View {
        ScrollViewReader { proxy in
            List {
                if vm.isLoading && vm.galleryItems.isEmpty {
                    HStack { Spacer(); ProgressView("Scanning library…"); Spacer() }
                        .listRowSeparator(.hidden)
                }
                ForEach(vm.galleryItems) { galleryItem in
                    galleryRow(for: galleryItem)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .refreshable { vm.loadMedia(forceRefresh: true) }
            .onChange(of: scrollToMonthKey) { key in
                if let key { proxy.scrollTo("month-\(key)", anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private func galleryRow(for item: GalleryItem) -> some View {
        switch item {
        case .yearHeader(let y):
            YearHeaderRow(header: y) { vm.toggleYearExpansion(y.year) }
                .id(item.id)
        case .header(let h):
            MonthHeaderRow(header: h,
                           onTap: { vm.toggleMonthExpansion(h.monthKey) },
                           onMarkDone: { vm.markMonthDone(key: h.monthKey) })
                .id(item.id)
        case .subHeader(let s):
            SubHeaderRow(sub: s) { vm.toggleSubGroupExpansion(s.subKey) }
                .id(item.id)
        case .media(let m):
            MediaThumbnailView(cell: m) {
                selectedItem = m.mediaItem
            }
            .id(item.id)
        case .footer:
            Divider().padding(.vertical, 4).id(item.id)
        }
    }

    // MARK: - Permission denied

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.slash").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Photos Access Required")
                .font(.title2).bold()
            Text("MediaCurator needs access to your photo library to show and curate your media.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var galleryToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button {
                        vm.setSortMode(mode)
                    } label: {
                        Label(mode.displayName,
                              systemImage: vm.sortMode == mode ? "checkmark" : "")
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            // Type filter chips
            Menu {
                Toggle("Photos",  isOn: Binding(get: { vm.includePhoto }, set: { vm.setIncludePhoto($0) }))
                Toggle("Videos",  isOn: Binding(get: { vm.includeVideo }, set: { vm.setIncludeVideo($0) }))
                Toggle("PDFs",    isOn: Binding(get: { vm.includePdf },   set: { vm.setIncludePdf($0) }))
                Toggle("Audio",   isOn: Binding(get: { vm.includeAudio }, set: { vm.setIncludeAudio($0) }))
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }
}

// MARK: - SortMode display names

extension SortMode {
    var displayName: String {
        switch self {
        case .dateNewest:      return "Newest first"
        case .dateOldest:      return "Oldest first"
        case .sizeAbsolute:    return "Largest files"
        case .sizeWithinMonth: return "Largest within month"
        case .countPerMonth:   return "Most items per month"
        }
    }
}

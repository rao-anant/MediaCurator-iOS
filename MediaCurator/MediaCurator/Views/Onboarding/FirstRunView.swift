import SwiftUI
import Combine
import Photos

/// First-run animated explainer of the Review → Hide loop (spec §13).
/// Auto-plays. On first run it's mandatory-until-opted-out ("Don't show again"); in replay
/// mode (from Help) it's freely dismissable.
struct FirstRunView: View {
    let replayMode: Bool
    let onFinish: (_ optedOut: Bool) -> Void

    @StateObject private var model = DemoModel()
    @State private var dontShowAgain = false
    @State private var frames: [String: CGRect] = [:]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                header
                phoneSurface
                Spacer(minLength: 8)
                transport
                primaryRow
            }
            .padding()

            if replayMode || model.finished {
                VStack {
                    HStack {
                        Spacer()
                        Button { onFinish(dontShowAgain) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .onAppear { model.play() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("How curating works").font(.title2).bold()
            Text("Review a month, hide it, and it steps out of your way — so you never scroll past the same photos again.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var phoneSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProgressView(value: model.progress, total: 100).tint(.accentColor)
                Text("\(Int(model.progress))% curated")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .trailing)
            }
            Text(model.caption).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.default, value: model.caption)

            ForEach(Array(model.months.enumerated()), id: \.element.id) { idx, month in
                DemoMonthCard(index: idx, month: month)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .coordinateSpace(name: "demo")
        .onPreferenceChange(DemoFrameKey.self) { frames = $0 }
        .overlay {
            // Driving finger: sits at the model's current target element and pulses a tap.
            if model.fingerVisible, let rect = frames[model.fingerTargetID] {
                Image(systemName: "hand.point.up.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.primary)
                    .shadow(radius: 3)
                    .scaleEffect(model.fingerTapping ? 0.7 : 1.0, anchor: .top)
                    .position(x: rect.midX + 10, y: rect.midY + 14)
                    .animation(.easeInOut(duration: 0.45), value: model.fingerTargetID)
                    .animation(.easeInOut(duration: 0.15), value: model.fingerTapping)
                    .allowsHitTesting(false)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 28) {
            Button { model.rewind() } label: { Image(systemName: "backward.end.fill") }
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            }
        }
        .font(.title3).foregroundStyle(Color.accentColor)
    }

    private var primaryRow: some View {
        VStack(spacing: 10) {
            if !replayMode {
                Toggle("Don't show again", isOn: $dontShowAgain).font(.subheadline)
            }
            Button {
                onFinish(dontShowAgain)
            } label: {
                Text(replayMode ? "Done" : "Get started")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Frame reporting (so the finger lands on real elements)

private struct DemoFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    func demoFrame(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: DemoFrameKey.self, value: [id: g.frame(in: .named("demo"))])
        })
    }
}

// MARK: - Month card

private struct DemoMonthCard: View {
    let index: Int
    let month: DemoModel.Month
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: month.isOpen ? "chevron.down" : "chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
                Text(month.label).font(.subheadline).bold()
                Spacer()
                if month.showPill {
                    Text("Hide month")
                        .font(.caption2).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentColor, in: Capsule())
                        .demoFrame("pill-\(index)")
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .demoFrame("header-\(index)")

            if month.isOpen && !month.isHidden {
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(Array(month.tiles.enumerated()), id: \.element.id) { i, tile in
                        ZStack {
                            if let img = tile.image {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                RoundedRectangle(cornerRadius: 6).fill(tile.color)
                                Text(tile.emoji).font(.title3)
                            }
                            if tile.selected {
                                Rectangle().fill(.red.opacity(0.45))
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .demoFrame("tile-\(index)-\(i)")
                    }
                }
                .transition(.opacity)

                if month.anySelected {
                    HStack {
                        Spacer()
                        Label("Delete", systemImage: "trash")
                            .font(.caption).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.red, in: Capsule())
                            .demoFrame("delete-\(index)")
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(10)
        .background(month.isHidden ? Color.clear : Color(.tertiarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .opacity(month.isHidden ? 0.0 : 1.0)
        .frame(height: month.isHidden ? 0 : nil)
        .animation(.easeInOut(duration: 0.4), value: month.isOpen)
        .animation(.easeInOut(duration: 0.5), value: month.isHidden)
        .animation(.easeInOut(duration: 0.3), value: month.showPill)
        .animation(.easeInOut(duration: 0.25), value: month.anySelected)
    }
}

// MARK: - Demo driver

@MainActor
final class DemoModel: ObservableObject {
    struct Tile: Identifiable {
        let id = UUID()
        let color: Color
        let emoji: String
        var image: UIImage? = nil   // real library thumbnail when available
        var selected = false
    }
    struct Month: Identifiable {
        let id = UUID()
        let label: String
        var tiles: [Tile]
        var isOpen = false
        var isHidden = false
        var showPill = false
        var anySelected: Bool { tiles.contains { $0.selected } }
    }

    @Published var months: [Month]
    @Published var progress: Double = 0
    @Published var caption = "Here are your months, waiting to be reviewed."
    @Published var isPlaying = false
    @Published var finished = false
    @Published var fingerTargetID = "header-1"
    @Published var fingerTapping = false
    @Published var fingerVisible = false

    private var task: Task<Void, Never>? = nil
    // Muted-but-distinct colours + Android's little-picture emoji set.
    private static let palette: [Color] = [
        Color(red: 0.42, green: 0.60, blue: 0.86), Color(red: 0.50, green: 0.69, blue: 0.36),
        Color(red: 0.79, green: 0.66, blue: 0.36), Color(red: 0.61, green: 0.54, blue: 0.83),
        Color(red: 0.85, green: 0.45, blue: 0.55), Color(red: 0.36, green: 0.68, blue: 0.67),
        Color(red: 0.86, green: 0.58, blue: 0.30), Color(red: 0.45, green: 0.63, blue: 0.80),
    ]
    private static let emojis = ["🌅","🐶","🎂","🏖","🐱","🌸","🍕","🚗","🎸","🏔","🐠","🌮"]

    init() {
        months = ["March 2024", "April 2024", "June 2024"].enumerated().map { (mi, label) in
            Month(label: label, tiles: (0..<8).map { i in
                Tile(color: DemoModel.palette[i % 8],
                     emoji: DemoModel.emojis[(mi * 3 + i) % DemoModel.emojis.count])
            })
        }
        loadThumbnails()
    }

    /// Fill tiles with real library thumbnails so they read as actual photos (emoji don't
    /// render on the simulator). Falls back to the coloured swatch when no photos/access.
    /// Retries because the demo can init before Home's photo-auth request resolves (on iOS 26
    /// `authorizationStatus` reads notDetermined until the first requestAuthorization).
    private func loadThumbnails(retriesLeft: Int = 8) {
        var flat: [(Int, Int)] = []
        for mi in months.indices { for ti in months[mi].tiles.indices { flat.append((mi, ti)) } }

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = flat.count
        let assets = PHAsset.fetchAssets(with: .image, options: opts)
        // Empty usually means photo access hasn't resolved yet (the demo can init before
        // Home's auth request completes) — retry until assets appear.
        guard assets.count > 0 else {
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.loadThumbnails(retriesLeft: retriesLeft - 1)
                }
            }
            return
        }

        let manager = PHImageManager.default()
        let ro = PHImageRequestOptions()
        ro.deliveryMode = .opportunistic
        ro.resizeMode = .fast
        ro.isNetworkAccessAllowed = true

        assets.enumerateObjects { asset, idx, _ in
            guard idx < flat.count else { return }
            let (mi, ti) = flat[idx]
            manager.requestImage(for: asset, targetSize: CGSize(width: 200, height: 200),
                                 contentMode: .aspectFill, options: ro) { [weak self] img, _ in
                guard let self, let img else { return }
                Task { @MainActor in
                    if mi < self.months.count, ti < self.months[mi].tiles.count {
                        self.months[mi].tiles[ti].image = img
                    }
                }
            }
        }
    }

    func play() {
        guard task == nil else { return }
        isPlaying = true
        task = Task { await run() }
    }
    func togglePlay() { isPlaying ? stop() : play() }
    func stop() { isPlaying = false; task?.cancel(); task = nil }

    func rewind() {
        stop()
        for i in months.indices {
            months[i].isOpen = false; months[i].isHidden = false; months[i].showPill = false
            for j in months[i].tiles.indices { months[i].tiles[j].selected = false }
        }
        progress = 0
        caption = "Here are your months, waiting to be reviewed."
        finished = false
        fingerVisible = false
        fingerTapping = false
    }

    private func beat(_ seconds: Double) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled
    }

    /// Move the finger to a named element and pulse a tap.
    @discardableResult
    private func fingerTap(_ id: String) async -> Bool {
        fingerVisible = true
        withAnimation { fingerTargetID = id }
        guard await beat(0.5) else { return false }
        withAnimation { fingerTapping = true }
        guard await beat(0.18) else { return false }
        withAnimation { fingerTapping = false }
        return await beat(0.1)
    }

    private func run() async {
        let order = [1, 0, 2]           // middle first, then the ends
        let progresses = [34.0, 67.0, 100.0]
        let captions = [
            "Open one and look through its photos.",
            "Next month — delete the junk… then hide it.",
            "…and the last one.",
        ]
        fingerVisible = true
        guard await beat(1.0) else { return }

        for (step, idx) in order.enumerated() {
            caption = captions[step]
            guard await fingerTap("header-\(idx)") else { return }
            withAnimation { months[idx].isOpen = true }
            guard await beat(1.0) else { return }

            let toSelect = min(step + 1, months[idx].tiles.count)
            for k in Array(months[idx].tiles.indices.shuffled().prefix(toSelect)) {
                guard await fingerTap("tile-\(idx)-\(k)") else { return }
                withAnimation { months[idx].tiles[k].selected = true }
            }
            caption = "Pick the ones you don't want and Delete."
            guard await fingerTap("delete-\(idx)") else { return }
            withAnimation { months[idx].tiles.removeAll { $0.selected } }
            guard await beat(0.8) else { return }

            withAnimation { months[idx].showPill = true }
            caption = "Then hide the whole month."
            guard await beat(0.5) else { return }
            guard await fingerTap("pill-\(idx)") else { return }
            withAnimation {
                months[idx].isHidden = true
                progress = progresses[step]
            }
            caption = "It steps out of your way — this app gets cleaner."
            guard await beat(1.4) else { return }
        }

        caption = "All caught up — clean and curated."
        fingerVisible = false
        isPlaying = false
        finished = true
        task = nil
    }
}

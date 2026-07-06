import SwiftUI
import Combine

/// First-run animated explainer of the Review → Hide loop (spec §13).
/// Auto-plays. On first run it's mandatory-until-opted-out ("Don't show again"); in replay
/// mode (from Help) it's freely dismissable.
struct FirstRunView: View {
    let replayMode: Bool
    let onFinish: (_ optedOut: Bool) -> Void

    @StateObject private var model = DemoModel()
    @State private var dontShowAgain = false

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

            // ✕ appears only once finished (or any time in replay mode).
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
            // Progress + label
            HStack {
                ProgressView(value: model.progress, total: 100).tint(.accentColor)
                Text("\(Int(model.progress))% curated")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .trailing)
            }
            Text(model.caption).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.default, value: model.caption)

            ForEach(model.months) { month in
                DemoMonthCard(month: month)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            // Driving finger: positioned by the model, taps in sync with each action.
            GeometryReader { geo in
                if model.fingerVisible {
                    Image(systemName: "hand.point.up.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.primary)
                        .shadow(radius: 3)
                        .scaleEffect(model.fingerTapping ? 0.7 : 1.0)
                        .position(x: geo.size.width * model.fingerAnchor.x,
                                  y: geo.size.height * model.fingerAnchor.y)
                        .animation(.easeInOut(duration: 0.5), value: model.fingerAnchor)
                        .animation(.easeInOut(duration: 0.15), value: model.fingerTapping)
                        .allowsHitTesting(false)
                }
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
                Toggle("Don't show again", isOn: $dontShowAgain)
                    .font(.subheadline)
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

// MARK: - Month card

private struct DemoMonthCard: View {
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
                        .transition(.scale.combined(with: .opacity))
                }
            }
            if month.isOpen && !month.isHidden {
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(month.tiles) { tile in
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(tile.color)
                            Image(systemName: tile.symbol)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.9))
                            if tile.selected {
                                RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.45))
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                }
                .transition(.opacity)
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
    }
}

// MARK: - Demo driver

@MainActor
final class DemoModel: ObservableObject {
    struct Tile: Identifiable {
        let id = UUID()
        let color: Color
        let symbol: String   // SF Symbol — renders reliably (emoji showed as tofu)
        var selected = false
    }
    struct Month: Identifiable {
        let id = UUID()
        let label: String
        var tiles: [Tile]
        var isOpen = false
        var isHidden = false
        var showPill = false
    }

    @Published var months: [Month]
    @Published var progress: Double = 0
    @Published var caption = "Here are your months, waiting to be reviewed."
    @Published var isPlaying = false
    @Published var finished = false
    /// Finger overlay: normalized position within the phone surface + a tap pulse.
    @Published var fingerAnchor = CGPoint(x: 0.5, y: 0.5)
    @Published var fingerTapping = false
    @Published var fingerVisible = false

    private var task: Task<Void, Never>? = nil
    private static let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .yellow, .mint]
    private static let symbols = ["photo.fill", "camera.fill", "heart.fill", "star.fill",
                                  "sun.max.fill", "leaf.fill", "car.fill", "sparkles"]

    init() {
        months = ["March 2024", "April 2024", "June 2024"].map { label in
            Month(label: label, tiles: (0..<8).map { i in
                Tile(color: DemoModel.palette[i % 8], symbol: DemoModel.symbols[i % 8])
            })
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

    /// Move the finger to a normalized point and pulse a "tap".
    @discardableResult
    private func fingerTap(x: Double, y: Double) async -> Bool {
        fingerVisible = true
        withAnimation { fingerAnchor = CGPoint(x: x, y: y) }
        guard await beat(0.45) else { return false }
        withAnimation { fingerTapping = true }
        guard await beat(0.18) else { return false }
        withAnimation { fingerTapping = false }
        return true
    }

    private func run() async {
        // Open middle month first, then the ends (never strictly top→bottom).
        let order = [1, 0, 2]
        let progresses = [34.0, 67.0, 100.0]
        let captions = [
            "Open one and look through its photos.",
            "Next month — delete the junk… then hide it.",
            "Last one — same idea.",
        ]
        fingerVisible = true
        guard await beat(1.0) else { return }

        for (step, idx) in order.enumerated() {
            caption = captions[step]
            // Tap the month header (approx: upper area) to open it.
            guard await fingerTap(x: 0.5, y: 0.20) else { return }
            withAnimation { months[idx].isOpen = true }
            guard await beat(1.2) else { return }

            // Select a few tiles (1, 2, 3 across the three months).
            let toSelect = min(step + 1, months[idx].tiles.count)
            for (n, k) in Array(months[idx].tiles.indices.shuffled().prefix(toSelect)).enumerated() {
                // Rough grid position for the finger (4 columns, 2 rows) over the tile area.
                let fx = 0.2 + Double(n % 4) * 0.2
                guard await fingerTap(x: fx, y: 0.5) else { return }
                withAnimation { months[idx].tiles[k].selected = true }
            }
            caption = "Pick the ones you don't want and Delete."
            guard await fingerTap(x: 0.5, y: 0.82) else { return }   // tap Delete
            withAnimation { months[idx].tiles.removeAll { $0.selected } }
            guard await beat(0.8) else { return }

            withAnimation { months[idx].showPill = true }
            caption = "Then hide the whole month."
            guard await fingerTap(x: 0.82, y: 0.22) else { return }  // tap Hide month pill
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

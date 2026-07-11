import SwiftUI
import Combine

/// First-run **self-paced onboarding deck** (spec §13). Four slides taught with Next / Back and
/// progress dots — nothing races off-screen. Only the "Review, then hide" slide animates; the rest
/// are calm states the reader dwells on. Mandatory-until-last on first run (a "Don't show again"
/// checkbox on the last slide opts out, persisted durably); in replay mode (from Help) a ✕ closes
/// it anytime and there's no checkbox.
struct FirstRunView: View {
    let replayMode: Bool
    let onFinish: (_ optedOut: Bool) -> Void

    @State private var slide = 0
    @State private var dontShowAgain = false
    private let slideCount = 4
    private var isLast: Bool { slide == slideCount - 1 }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                header
                surface
                Spacer(minLength: 4)
                if isLast && !replayMode {
                    Toggle("Don't show again", isOn: $dontShowAgain)
                        .font(.subheadline).padding(.horizontal, 4)
                }
                navRow
            }
            .padding()

            // Replay mode only: dismiss anytime. (First run is mandatory until the last slide.)
            if replayMode {
                VStack {
                    HStack {
                        Spacer()
                        Button { onFinish(false) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("How curating works").font(.title2).bold()
            Text("Tap through at your own pace — review a month, hide it, and it steps out of your way.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var surface: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(0..<slideCount, id: \.self) { i in
                    Circle().fill(i == slide ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Group {
                switch slide {
                case 0: BacklogSlide()
                case 1: ReviewHideSlide()
                case 2: RemembersSlide()
                default: RecapSlide()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 380, alignment: .top)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var navRow: some View {
        HStack {
            if slide > 0 {
                Button { withAnimation { slide -= 1 } } label: {
                    Label("Back", systemImage: "chevron.left").font(.subheadline)
                }
            }
            Spacer()
            Button {
                if isLast { onFinish(replayMode ? false : dontShowAgain) }
                else { withAnimation { slide += 1 } }
            } label: {
                Text(isLast ? "Done" : "Next")
                    .font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
            }
        }
    }
}

// MARK: - Shared slide pieces

private func demoCaption(_ text: String) -> some View {
    Text(text).font(.subheadline).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
}

/// A collapsed month row (chevron + label, optional "new" badge).
private struct CollapsedMonthCard: View {
    let label: String
    var isNew = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            Text(label).font(.subheadline).bold()
            if isNew {
                Text("new").font(.caption2).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The dashed "🙈 Hidden · <month>" shelf — names a filed month so the return never looks
/// resurrected.
private struct HiddenShelf: View {
    let month: String
    var body: some View {
        HStack {
            Text("🙈 Hidden · \(month)").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }
}

// MARK: - Slide 0: Backlog

private struct BacklogSlide: View {
    @State private var appear = false
    private let months = ["March 2024", "April 2024", "May 2024"]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("2024").font(.headline)
            ForEach(Array(months.enumerated()), id: \.offset) { i, m in
                CollapsedMonthCard(label: m)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 8)
                    .animation(.easeOut(duration: 0.4).delay(Double(i) * 0.15), value: appear)
            }
            Spacer(minLength: 12)
            demoCaption("Months piling up · years of photos, waiting to be sorted.")
        }
        .onAppear { appear = true }
    }
}

// MARK: - Slide 2: It remembers

private struct RemembersSlide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HiddenShelf(month: "March")
            Text("2024").font(.headline)
            CollapsedMonthCard(label: "April 2024")
            CollapsedMonthCard(label: "May 2024")
            CollapsedMonthCard(label: "July 2024", isNew: true)
            Spacer(minLength: 12)
            demoCaption("Come back tomorrow or next month — March stays hidden, and what's new is waiting.")
        }
    }
}

// MARK: - Slide 3: Recap

private struct RecapSlide: View {
    private let bullets = [
        "Curate any month, in any order.",
        "Hidden only in this app — never deleted, filed away and reopenable.",
        "Come back later and it stays hidden.",
        "You pick up right where you left off, plus what's new.",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Curate once. Stays curated.")
                .font(.title3).bold().foregroundStyle(.green)
            ForEach(bullets, id: \.self) { b in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(b).font(.subheadline)
                }
            }
            Spacer(minLength: 8)
        }
    }
}

// MARK: - Slide 1: Review, then hide (the one animated slide)

private struct ReviewHideSlide: View {
    @StateObject private var m = ReviewHideModel()
    @State private var frames: [String: CGRect] = [:]
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if m.hidden {
                HiddenShelf(month: "March")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Text("2024").font(.headline)
            if !m.hidden {
                marchCard.transition(.opacity)
            }
            if m.showGreenBar { greenBar.transition(.opacity) }
            Spacer(minLength: 6)
            demoCaption(m.caption)
        }
        .coordinateSpace(name: "s1")
        .onPreferenceChange(S1FrameKey.self) { frames = $0 }
        .overlay { finger }
        .animation(.easeInOut(duration: 0.5), value: m.hidden)
        .animation(.easeInOut(duration: 0.3), value: m.showGreenBar)
        .onAppear { m.start() }
        .onDisappear { m.stop() }
    }

    private var marchCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                Text("March 2024").font(.subheadline).bold()
                Spacer()
                // Hide-month pill is shown from the start so its presence registers.
                Text("Hide month")
                    .font(.caption2).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
                    .s1Frame("pill")
            }
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(Array(m.tiles.enumerated()), id: \.element.id) { i, tile in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(tile.color)
                        Text(tile.emoji).font(.title3)
                        if tile.selected {
                            RoundedRectangle(cornerRadius: 6).stroke(.red, lineWidth: 3)
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .s1Frame("tile-\(i)")
                }
            }
            if m.anySelected {
                HStack {
                    Spacer()
                    Label("Delete", systemImage: "trash")
                        .font(.caption).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.red, in: Capsule())
                        .s1Frame("delete")
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.25), value: m.anySelected)
    }

    private var greenBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            Text("Hidden only in this app — never deleted, still in your gallery.")
                .font(.caption).foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var finger: some View {
        if m.fingerVisible, let rect = frames[m.fingerTargetID] {
            Image(systemName: "hand.point.up.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.0))
                .shadow(color: .black.opacity(0.6), radius: 2)
                .scaleEffect(m.fingerTapping ? 0.7 : 1.0, anchor: .top)
                .position(x: rect.midX + 10, y: rect.midY + 14)
                .animation(.easeInOut(duration: 0.4), value: m.fingerTargetID)
                .animation(.easeInOut(duration: 0.15), value: m.fingerTapping)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Slide 1 animation driver

@MainActor
private final class ReviewHideModel: ObservableObject {
    struct Tile: Identifiable {
        let id = UUID()
        let color: Color
        let emoji: String
        var selected = false
    }

    @Published var tiles: [Tile] = []
    @Published var hidden = false
    @Published var showGreenBar = false
    @Published var caption = "Open a month, delete the junk, then hide it."
    @Published var fingerVisible = false
    @Published var fingerTapping = false
    @Published var fingerTargetID = "pill"

    private var task: Task<Void, Never>? = nil
    var anySelected: Bool { tiles.contains { $0.selected } }

    private static let palette: [Color] = [
        Color(red: 0.42, green: 0.60, blue: 0.86), Color(red: 0.50, green: 0.69, blue: 0.36),
        Color(red: 0.79, green: 0.66, blue: 0.36), Color(red: 0.61, green: 0.54, blue: 0.83),
        Color(red: 0.85, green: 0.45, blue: 0.55), Color(red: 0.36, green: 0.68, blue: 0.67),
        Color(red: 0.86, green: 0.58, blue: 0.30), Color(red: 0.45, green: 0.63, blue: 0.80),
    ]
    private static let emojis = ["🌅","🐶","🎂","🏖️","🐱","🌸","🍕","🚗"]

    private func freshTiles() -> [Tile] {
        (0..<8).map { i in Tile(color: Self.palette[i % 8], emoji: Self.emojis[i % Self.emojis.count]) }
    }

    /// Begin (or restart) the play from a clean state. Called on each entry to the slide.
    func start() {
        task?.cancel()
        tiles = freshTiles()
        hidden = false; showGreenBar = false
        fingerVisible = false; fingerTapping = false
        caption = "Open a month, delete the junk, then hide it."
        task = Task { await run() }
    }
    func stop() { task?.cancel(); task = nil }

    private func beat(_ s: Double) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
        return !Task.isCancelled
    }

    @discardableResult
    private func tap(_ id: String) async -> Bool {
        fingerVisible = true
        withAnimation { fingerTargetID = id }
        guard await beat(0.55) else { return false }
        withAnimation { fingerTapping = true }
        guard await beat(0.18) else { return false }
        withAnimation { fingerTapping = false }
        return await beat(0.12)
    }

    private func run() async {
        guard await beat(0.8) else { return }
        // Tap two "junk" tiles → each gets a red ring + ✓, and Delete fades in.
        for k in [2, 5] where k < tiles.count {
            guard await tap("tile-\(k)") else { return }
            withAnimation { tiles[k].selected = true }
        }
        caption = "Pick the ones you don't want — then Delete."
        guard await beat(0.3) else { return }
        guard await tap("delete") else { return }
        withAnimation { tiles.removeAll { $0.selected } }
        guard await beat(0.6) else { return }
        // Hide the whole month → it collapses into the dashed Hidden shelf.
        caption = "Then hide the whole month."
        guard await beat(0.4) else { return }
        guard await tap("pill") else { return }
        fingerVisible = false
        withAnimation { hidden = true }
        guard await beat(0.45) else { return }
        withAnimation { showGreenBar = true }
        caption = "That's it — March is filed away, not deleted."
        task = nil
    }
}

// MARK: - Frame reporting (so the finger lands on real elements)

private struct S1FrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    func s1Frame(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: S1FrameKey.self, value: [id: g.frame(in: .named("s1"))])
        })
    }
}

import SwiftUI

/// Home hub — mirrors Android's `HomeActivity`.
/// Shows a hero card (curation progress) and cards for Gallery, Duplicates, Hidden, Trash.
struct HomeView: View {

    @StateObject private var vm = HomeViewModel()
    @State private var path = NavigationPath()
    @State private var showingStats = false
    @State private var showDemo = false

    private let prefs = PreferencesManager()
    /// The mandatory first-run demo auto-plays once per process (spec §13).
    private static var demoShownThisProcess = false

    private let twoColumns = [GridItem(.flexible(), spacing: 12),
                              GridItem(.flexible(), spacing: 12)]

    private var placeReady: Bool { (vm.state?.placeCount ?? 0) > 0 }
    private var placeSub: String {
        let n = vm.state?.placeCount ?? 0
        return n == 0 ? "Scanning photos…" : "\(Formatters.countShort(n)) located"
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    if let state = vm.state {
                        // Hero = the curation entry point (opens the gallery at the resume month).
                        HeroCard(state: state) {
                            path.append(NavDestination.gallery(monthKey: state.resumeMonthKey))
                        }
                        // Browse by Location — compact chips right under the hero (matches
                        // Android), dimmed until ≥1 place is indexed (spec §7).
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Browse by Location")
                                .font(.subheadline).bold().foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                LocationChip(title: "By City", icon: "building.2", subtitle: placeSub,
                                             disabled: !placeReady) { path.append(NavDestination.placeCities) }
                                LocationChip(title: "Drill down", icon: "globe", subtitle: "Country › City",
                                             disabled: !placeReady) { path.append(NavDestination.placeDrill) }
                            }
                        }

                        // Hidden months — full width.
                        NavCard(title: "Hidden months", subtitle: state.hiddenSub, icon: "eye.slash") {
                            path.append(NavDestination.hidden)
                        }

                        LazyVGrid(columns: twoColumns, spacing: 12) {
                            GridCard(title: "Free up space", subtitle: "Biggest files first", icon: "internaldrive") {
                                path.append(NavDestination.gallery(monthKey: nil))
                            }
                            GridCard(title: "Find duplicates", subtitle: state.dupSub, icon: "doc.on.doc") {
                                path.append(NavDestination.duplicates)
                            }
                        }

                        // Trash — full width.
                        NavCard(title: "Trash", subtitle: state.trashSub, icon: "trash", disabled: state.trashEmpty) {
                            path.append(NavDestination.trash)
                        }
                    } else {
                        ProgressView("Loading…")
                            .padding(.top, 80)
                    }
                }
                .padding()
            }
            .navigationTitle("MediaCurator")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingStats = true } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: NavDestination.settings) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingStats) { StatsView() }
            .navigationDestination(for: NavDestination.self) { dest in
                switch dest {
                case .gallery(let key):  GalleryView(scrollToMonthKey: key)
                case .duplicates:        DuplicatesView()
                case .hidden:            HiddenView()
                case .trash:             TrashView()
                case .settings:          SettingsView()
                case .placeCities:       PlaceBrowseView(mode: .cities)
                case .placeDrill:        PlaceBrowseView(mode: .drill)
                }
            }
        }
        .onAppear {
            vm.load()
            // Mandatory first-run demo: once per process, unless opted out (spec §13).
            if !Self.demoShownThisProcess && !prefs.isDemoOptedOut() {
                Self.demoShownThisProcess = true
                showDemo = true
            }
        }
        // Reload whenever we return to the root (NavigationStack doesn't reliably re-fire
        // onAppear on pop), so curation progress, hidden count, and trash count refresh
        // after the user hides a month or stages a delete on a pushed screen.
        .onChange(of: path.count) { newCount in
            if newCount == 0 { vm.load() }
        }
        .fullScreenCover(isPresented: $showDemo) {
            FirstRunView(replayMode: false) { optedOut in
                if optedOut { prefs.setDemoOptedOut(true) }
                showDemo = false
            }
        }
    }
}

// MARK: - Navigation destinations

enum NavDestination: Hashable {
    case gallery(monthKey: String?)
    case duplicates
    case hidden
    case trash
    case settings
    case placeCities
    case placeDrill
}

// MARK: - Sub-views

private struct HeroCard: View {
    let state: HomeState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Library overview line, e.g. "18.2k items · 63 GB · 6.2k reviewed"
                Text(state.summary)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(state.heroTitle)
                    .font(.title2).bold()
                if state.heroProgress >= 0 {
                    ProgressView(value: Double(state.heroProgress), total: 100)
                        .tint(.accentColor)
                    Text(state.heroProgressLabel)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !state.heroCaption.isEmpty {
                    Text(state.heroCaption).font(.caption).foregroundStyle(.secondary)
                }
                if !state.resumeLabel.isEmpty {
                    Text(state.resumeLabel).font(.subheadline)
                }
                // Visual call-to-action (whole card is tappable, not just this).
                Text(state.heroButton)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
                    .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Compact "Browse by Location" chip (By City / Drill down).
private struct LocationChip: View {
    let title: String
    let icon: String
    let subtitle: String
    var disabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline).bold()
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

/// Square-ish card for the 2x2 secondary-action grid (icon top, title, subtitle).
private struct GridCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var disabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

private struct NavCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var disabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

import SwiftUI

/// Home hub — mirrors Android's `HomeActivity`.
/// Shows a hero card (curation progress) and cards for Gallery, Duplicates, Hidden, Trash.
struct HomeView: View {

    @StateObject private var vm = HomeViewModel()
    @State private var path = NavigationPath()
    @State private var showingStats = false

    private let twoColumns = [GridItem(.flexible(), spacing: 12),
                              GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    if let state = vm.state {
                        // Hero = the curation entry point (opens the gallery at the resume month).
                        HeroCard(state: state) {
                            path.append(NavDestination.gallery(monthKey: state.resumeMonthKey))
                        }
                        // Secondary actions. (Search is Phase 2 — it depends on the Files-app /
                        // PDF-text integration that v1 does not include; see PORTING_NOTES §12.)
                        LazyVGrid(columns: twoColumns, spacing: 12) {
                            GridCard(title: "Free up space", subtitle: "Biggest files first", icon: "internaldrive") {
                                path.append(NavDestination.gallery(monthKey: nil))
                            }
                            GridCard(title: "Find duplicates", subtitle: state.dupSub, icon: "doc.on.doc") {
                                path.append(NavDestination.duplicates)
                            }
                            GridCard(title: "Hidden months", subtitle: state.hiddenSub, icon: "eye.slash") {
                                path.append(NavDestination.hidden)
                            }
                        }
                        // Trash spans full width below the grid.
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
                }
            }
        }
        .onAppear { vm.load() }
        // Reload whenever we return to the root (NavigationStack doesn't reliably re-fire
        // onAppear on pop), so curation progress, hidden count, and trash count refresh
        // after the user hides a month or stages a delete on a pushed screen.
        .onChange(of: path.count) { newCount in
            if newCount == 0 { vm.load() }
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

/// Square-ish card for the 2x2 secondary-action grid (icon top, title, subtitle).
private struct GridCard: View {
    let title: String
    let subtitle: String
    let icon: String
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

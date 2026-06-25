import SwiftUI

/// Home hub — mirrors Android's `HomeActivity`.
/// Shows a hero card (curation progress) and cards for Gallery, Duplicates, Hidden, Trash.
struct HomeView: View {

    @StateObject private var vm = HomeViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    if let state = vm.state {
                        HeroCard(state: state) {
                            path.append(NavDestination.gallery(monthKey: state.resumeMonthKey))
                        }
                        SummaryCard(label: "Summary", detail: state.summary)
                        NavCard(title: "Gallery",    subtitle: state.summary,     icon: "photo.stack") {
                            path.append(NavDestination.gallery(monthKey: nil))
                        }
                        NavCard(title: "Duplicates", subtitle: state.dupSub,      icon: "doc.on.doc") {
                            path.append(NavDestination.duplicates)
                        }
                        NavCard(title: "Hidden",     subtitle: state.hiddenSub,   icon: "eye.slash") {
                            path.append(NavDestination.hidden)
                        }
                        NavCard(title: "Trash",      subtitle: state.trashSub,    icon: "trash") {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: NavDestination.settings) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: NavDestination.self) { dest in
                switch dest {
                case .gallery(let key):  GalleryView(scrollToMonthKey: key)
                case .duplicates:        Text("Duplicates — coming soon")
                case .hidden:            Text("Hidden — coming soon")
                case .trash:             Text("Trash — coming soon")
                case .settings:          Text("Settings — coming soon")
                }
            }
        }
        .onAppear { vm.load() }
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
        VStack(alignment: .leading, spacing: 8) {
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
            Button(state.heroButton, action: onTap)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SummaryCard: View {
    let label: String
    let detail: String
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(detail).font(.subheadline)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NavCard: View {
    let title: String
    let subtitle: String
    let icon: String
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
    }
}

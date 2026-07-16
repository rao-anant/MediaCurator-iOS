//
//  MediaCuratorApp.swift
//  MediaCurator
//
//  Created by user280950 on 6/25/26.
//

import SwiftUI

@main
struct MediaCuratorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let prefs = PreferencesManager()

    init() {
        // On a fresh install, restore durable state (hidden months, curation flags, lifetime
        // cleaned-up totals, demo opt-out) from the keychain, which survives reinstall (FR-2).
        PreferencesManager().restoreDurableStateIfFreshInstall()
        // Register the background place-indexing task (must happen before launch finishes).
        BackgroundIndexer.register()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        // Snapshot durable state to the keychain when leaving the foreground, so the latest
        // hidden-months / curation state is captured before any future uninstall.
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                prefs.backupDurableState()
                // Stop foreground hashing so no large PhotoKit read is in flight during the
                // scene-update transition (the b22 watchdog cause). It resumes when Home reloads.
                HashingCoordinator.shared.cancel()
                // Let iOS finish place indexing later while idle + on power.
                BackgroundIndexer.schedule()
            }
        }
    }
}

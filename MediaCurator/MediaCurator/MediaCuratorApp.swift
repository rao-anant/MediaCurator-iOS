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
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        // Snapshot durable state to the keychain when leaving the foreground, so the latest
        // hidden-months / curation state is captured before any future uninstall.
        .onChange(of: scenePhase) { phase in
            if phase == .background { prefs.backupDurableState() }
        }
    }
}

//
//  MediaCuratorApp.swift
//  MediaCurator
//
//  Created by user280950 on 6/25/26.
//

import SwiftUI

@main
struct MediaCuratorApp: App {
    init() {
        // On a fresh install, re-apply a durable (iCloud) demo opt-out before the UI shows (FR-2).
        PreferencesManager().syncDurableDemoOptOut()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

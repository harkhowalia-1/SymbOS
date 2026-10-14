// Halcyon - Siri / Spotlight phrases and Spotlight indexing (app target only).
// Licensed under the GNU General Public License v3 or later.

import AppIntents
import CoreSpotlight

struct HalcyonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSymbianAppIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Start \(\.$target) with \(.applicationName)",
            ],
            shortTitle: "Open Symbian App",
            systemImageName: "app.badge"
        )
    }
}

enum SpotlightIndexer {
    /// Called whenever the installed-app list changes.
    static func update(apps: [SymbianApp]) {
        let entities = apps.map(SymbianAppEntity.init)
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default().deleteAllSearchableItems()
            try? await CSSearchableIndex.default().indexAppEntities(entities)
            HalcyonShortcuts.updateAppShortcutParameters()
        }
    }
}

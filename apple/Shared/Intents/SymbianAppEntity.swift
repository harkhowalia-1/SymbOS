// SymbOS - installed Symbian apps as App Intents entities.
//
// Compiled into the app and the widget extension. Entities are read from the
// App Group (SharedStore), so they work without the emulator running. Being
// IndexedEntity, they also appear in Spotlight search.
//
// Licensed under the GNU General Public License v3 or later.

import AppIntents
import Foundation

struct SymbianAppEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Symbian App"
    static var defaultQuery = SymbianAppQuery()

    /// The app's UID in hex, e.g. "101F4CD5".
    let id: String
    let name: String

    init(app: SymbianApp) {
        id = app.uidHex
        name = app.name
    }

    var uid: UInt32? { SymbianApp.parseUID(id) }

    var displayRepresentation: DisplayRepresentation {
        if let uid, let data = SharedStore.iconPNGData(uid: uid) {
            return DisplayRepresentation(title: "\(name)", image: .init(data: data))
        }
        return DisplayRepresentation(title: "\(name)")
    }
}

struct SymbianAppQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SymbianAppEntity] {
        let wanted = Set(identifiers)
        return SharedStore.loadApps().map(SymbianAppEntity.init).filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [SymbianAppEntity] {
        SharedStore.loadApps()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(SymbianAppEntity.init)
    }

    func suggestedEntities() async throws -> [SymbianAppEntity] {
        SharedStore.loadApps().map(SymbianAppEntity.init)
    }
}

/// The app installs a handler at launch; the widget extension never does.
enum IntentRouter {
    @MainActor static var openApp: (@MainActor (UInt32) -> Void)?
}

struct OpenSymbianAppIntent: AppIntent, OpenIntent {
    static var title: LocalizedStringResource = "Open Symbian App"
    static var description = IntentDescription("Opens an installed Symbian app in the emulator.")
    static var openAppWhenRun = true

    @Parameter(title: "App")
    var target: SymbianAppEntity

    init() {}

    init(app: SymbianAppEntity) {
        target = app
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let uid = target.uid {
            IntentRouter.openApp?(uid)
        }
        return .result()
    }
}

/// Configuration for the per-app widget.
struct SelectSymbianAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose App"
    static var description = IntentDescription("Pick the Symbian app this widget opens.")

    @Parameter(title: "App")
    var app: SymbianAppEntity?

    init() {}
}

// Halcyon - iPhone and iPad app.
// Licensed under the GNU General Public License v3 or later.

import SwiftUI

@main
struct HalcyonApp: App {
    @StateObject private var controller = EmulatorController.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        IntentRouter.openApp = { uid in
            EmulatorController.shared.handle(.launch(uid: uid))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .onOpenURL(perform: open)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: controller.appDidEnterBackground()
            case .active: controller.appDidBecomeActive()
            default: break
            }
        }
    }

    private func open(_ url: URL) {
        if let link = DeepLink(url: url) {
            controller.handle(link)
        } else if url.isFileURL {
            // "Open in Halcyon" from Files, Safari or Mail.
            controller.install(packages: [url])
        }
    }
}

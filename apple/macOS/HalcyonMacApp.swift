// Halcyon - Mac app.
// Licensed under the GNU General Public License v3 or later.

import SwiftUI
import AppKit

@main
struct HalcyonMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = EmulatorController.shared

    init() {
        IntentRouter.openApp = { uid in
            EmulatorController.shared.handle(.launch(uid: uid))
        }
    }

    var body: some Scene {
        Window(AppConfig.displayName, id: "phone") {
            RootView()
                .environmentObject(controller)
                .frame(minWidth: 340, minHeight: 620)
                .onOpenURL(perform: open)
        }
        .defaultSize(width: 420, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Install App…") { controller.requestImport() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Phone") {
                Button("Home Screen") { controller.goHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Divider()
                Button("Options (Left Softkey)") { controller.press(.leftSoftkey) }
                    .keyboardShortcut("1")
                Button("Menu Key") { controller.press(.menu) }
                    .keyboardShortcut("2")
                Button("Back (Right Softkey)") { controller.press(.rightSoftkey) }
                    .keyboardShortcut("3")
                Divider()
                Button("Close \(controller.runningApp?.name ?? "App")") { controller.closeRunningApp() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(controller.runningApp == nil)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(controller)
        }
    }

    private func open(_ url: URL) {
        if let link = DeepLink(url: url) {
            controller.handle(link)
        } else if url.isFileURL {
            controller.install(packages: [url])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        HCEmulator.shared.shutdown()
    }
}

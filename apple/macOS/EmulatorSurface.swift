// SymbOS - SwiftUI wrapper for the emulator's OpenGL view (macOS).
// Licensed under the GNU General Public License v3 or later.

import SwiftUI
import AppKit

struct EmulatorSurface: NSViewRepresentable {
    let view: HCEmulatorView
    @EnvironmentObject private var controller: EmulatorController

    func makeNSView(context: Context) -> HCEmulatorView {
        view
    }

    func updateNSView(_ nsView: HCEmulatorView, context: Context) {
        // Keyboard input goes to the guest while an app is on screen.
        if controller.isShowingApp {
            Task { @MainActor in nsView.window?.makeFirstResponder(nsView) }
        }
    }
}

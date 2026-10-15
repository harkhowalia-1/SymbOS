// SymbOS - SwiftUI wrapper for the emulator's CAEAGLLayer view (iOS).
// Licensed under the GNU General Public License v3 or later.

import SwiftUI
import UIKit

struct EmulatorSurface: UIViewRepresentable {
    let view: HCEmulatorView
    @EnvironmentObject private var controller: EmulatorController

    func makeUIView(context: Context) -> HCEmulatorView {
        view
    }

    func updateUIView(_ uiView: HCEmulatorView, context: Context) {
        // Hardware keyboards talk to the guest while an app is on screen.
        if controller.isShowingApp {
            Task { @MainActor in _ = uiView.becomeFirstResponder() }
        }
    }
}

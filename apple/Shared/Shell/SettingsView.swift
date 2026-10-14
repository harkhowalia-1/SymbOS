// Halcyon - settings.
// Licensed under the GNU General Public License v3 or later.

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var controller: EmulatorController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fullSymbianMode") private var fullSymbianMode = false
    @AppStorage("gyroPassthrough") private var gyroPassthrough = true
    @AppStorage("hapticPassthrough") private var hapticPassthrough = true
    @AppStorage("showFPS") private var showFPS = false
    @State private var wantsJIT = JITSupport.userWantsJIT
    @State private var showingFirmwareSetup = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Full Symbian mode", isOn: $fullSymbianMode)
                } header: {
                    Text("Mode")
                } footer: {
                    Text("Shows the whole emulated phone instead of the home screen, like running Windows full screen in Parallels. Experimental: the phone's own launcher may not start on every firmware.")
                }

                performanceSection

                Section("Phone") {
                    let devices = controller.emulator.devices()
                    ForEach(Array(devices.enumerated()), id: \.offset) { index, device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text(device.firmware).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index == controller.emulator.currentDeviceIndex() {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    Button("Add firmware…") { showingFirmwareSetup = true }
                    Toggle("Tilt sensor", isOn: $gyroPassthrough)
                        .onChange(of: gyroPassthrough) { _, on in controller.emulator.setGyroPassthrough(on) }
                    Toggle("Vibration", isOn: $hapticPassthrough)
                        .onChange(of: hapticPassthrough) { _, on in controller.emulator.setHapticPassthrough(on) }
                }

                if !controller.layout.hidden.isEmpty {
                    Section("Hidden apps") {
                        ForEach(controller.layout.hidden, id: \.self) { uid in
                            HStack {
                                Text(controller.app(uid: uid)?.name ?? String(format: "%08X", uid))
                                Spacer()
                                Button("Show") {
                                    controller.layout.unhide(uid)
                                    controller.saveLayout()
                                }
                            }
                        }
                    }
                }

                Section("Files") {
                    #if os(macOS)
                    Button("Show phone storage in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([controller.dataDirectory])
                    }
                    #else
                    Text("The phone's drives are in the Files app under On My iPhone › \(AppConfig.displayName) › Halcyon › drives. Put music, photos and documents in drive E.")
                        .font(.callout)
                    #endif
                }

                Section("About") {
                    LabeledContent("Version", value: AppConfig.version)
                    LabeledContent("Emulator core", value: controller.isMock ? "Not included (demo build)" : "EKA2L1")
                    Link("Source code (GPLv3)", destination: AppConfig.repositoryURL)
                    Link("Guide", destination: AppConfig.guide("start"))
                    Text("\(AppConfig.displayName) is free software under the GNU GPL v3, built on the EKA2L1 emulator. It is not affiliated with Nokia, HMD Global or Accenture. Symbian and Nokia are trademarks of their respective owners. You must supply your own firmware and apps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .sheet(isPresented: $showingFirmwareSetup) {
            FirmwareSetupView()
                .environmentObject(controller)
        }
    }

    @ViewBuilder
    private var performanceSection: some View {
        Section {
            Toggle("Use JIT when available", isOn: $wantsJIT)
                .onChange(of: wantsJIT) { _, on in controller.setJIT(on) }
            LabeledContent("CPU", value: controller.usingJIT ? "Dynarmic JIT" : "Interpreter")
            Toggle("Show frame rate", isOn: $showFPS)
            #if os(iOS)
            if !JITSupport.isAvailable {
                Button("Enable JIT with StikDebug") {
                    JITSupport.requestJITFromStikDebug()
                }
                Link("How to set up StikDebug", destination: AppConfig.guide("jit"))
            }
            #endif
        } header: {
            Text("Performance")
        } footer: {
            #if os(iOS)
            Text(JITSupport.isAvailable
                 ? "JIT is available in this session."
                 : "JIT needs a debugger attached at launch. Install StikDebug, pair it once, then launch \(AppConfig.displayName) from StikDebug. Without it, apps run on the slower interpreter.")
            #else
            Text("The Mac app always has JIT.")
            #endif
        }
    }
}

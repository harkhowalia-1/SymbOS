// SymbOS - put a Symbian app on the real iPhone home screen or in the Mac's
// Applications folder and Dock. Each route opens the same deep link.
// Licensed under the GNU General Public License v3 or later.

import SwiftUI

struct HomeScreenShortcutSheet: View {
    @EnvironmentObject private var controller: EmulatorController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let app: SymbianApp
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppIconView(app: app, editing: false, showsLabel: false)
                            .scaleEffect(0.8)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading) {
                            Text(app.name).font(.headline)
                            Text(DeepLink.url(for: app).absoluteString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                #if os(iOS)
                Section {
                    Button {
                        do {
                            try WebClipInstaller.shared.install(app: app, icon: controller.icon(for: app.uid))
                            status = "Safari opens the profile. Tap Allow, then open Settings › Profile Downloaded › Install. The icon appears on your Home Screen."
                        } catch {
                            status = "Couldn't prepare the icon: \(error.localizedDescription)"
                        }
                    } label: {
                        Label("Add icon to Home Screen", systemImage: "apps.iphone.badge.plus")
                    }
                } header: {
                    Text("Real home screen icon")
                } footer: {
                    Text("Installs a small configuration profile with one web clip that opens \(app.name) in \(AppConfig.displayName). Remove it any time in Settings › General › VPN & Device Management.")
                }

                Section {
                    Button {
                        openURL(URL(string: "shortcuts://")!)
                    } label: {
                        Label("Open Shortcuts", systemImage: "square.2.layers.3d")
                    }
                } header: {
                    Text("With the Shortcuts app")
                } footer: {
                    Text("Create a shortcut with the \"Open Symbian App\" action, pick \(app.name), then choose Add to Home Screen. Installed Symbian apps also appear in Spotlight search.")
                }
                #else
                Section {
                    Button {
                        do {
                            let url = try LauncherAppGenerator.create(for: app, icon: controller.icon(for: app.uid))
                            status = "Created \(url.lastPathComponent). Drag it to the Dock to keep it there."
                            LauncherAppGenerator.reveal(url)
                        } catch {
                            status = "Couldn't create the launcher: \(error.localizedDescription)"
                        }
                    } label: {
                        Label("Create app in Applications", systemImage: "app.badge")
                    }
                } header: {
                    Text("Mac app launcher")
                } footer: {
                    Text("Makes \"\(app.name).app\" in ~/Applications/\(AppConfig.displayName) Apps. It shows up in Launchpad and Spotlight, and opens \(app.name) in \(AppConfig.displayName), like Parallels' Windows applications folder.")
                }
                #endif

                if let status {
                    Section { Text(status).font(.callout) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add to Home Screen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }
}

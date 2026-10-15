// Halcyon - first-run setup: the user brings their own phone firmware.
//
// Nokia's firmware is copyrighted, so it is never bundled or fetched by the app on its
// own. This screen makes importing the user's own copy a one-time, low-effort step:
// pick the files (or a .zip), paste a link to their copy, or drop the files into the
// Firmware Inbox folder. See FirmwareImporter.
//
// Licensed under the GNU General Public License v3 or later.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct FirmwareSetupView: View {
    @EnvironmentObject private var controller: EmulatorController
    @ObservedObject private var importer = FirmwareImporter.shared
    @Environment(\.dismiss) private var dismiss
    /// Shown from Settings (has a close button) rather than as the first-run screen.
    var presentedAsSheet = false

    @State private var picking = false
    @State private var link = ""
    @State private var dropTargeted = false
    @FocusState private var linkFocused: Bool

    var body: some View {
        ZStack {
            Wallpaper()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    chooseFilesCard
                    linkCard
                    inboxCard
                    status
                    Link(destination: AppConfig.guide("firmware")) {
                        Label("How to dump firmware from your phone", systemImage: "questionmark.circle")
                    }
                    .font(.callout)
                    Text("Use firmware from a phone you own. \(AppConfig.displayName) doesn't include or download any Nokia software by itself; a link you paste is only used to fetch your own copy.")
                        .font(.footnote)
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                .padding(28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            if dropTargeted {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if presentedAsSheet {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(16)
                .accessibilityLabel("Close")
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: SymbianFileTypes.firmware,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                importer.importFiles(urls)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            importer.importFiles(urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .onChange(of: controller.phase) { _, phase in
            if presentedAsSheet, phase == .ready, importer.activity == nil, importer.notice == nil {
                dismiss()
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set up your phone")
                .font(.largeTitle.bold())
            Text("\(AppConfig.displayName) runs the firmware from your own Symbian phone: its ROM and its RPKG file. Add them once and they stay installed.")
                .opacity(0.9)
        }
    }

    private var chooseFilesCard: some View {
        Card {
            Button { picking = true } label: {
                Label("Choose firmware files", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.25))
            Text("Select the ROM and the RPKG together, or one .zip that contains them. You can also open them with \(AppConfig.displayName) from Files, AirDrop or Safari\(platformDropHint).")
                .font(.subheadline)
                .opacity(0.85)
        }
    }

    private var linkCard: some View {
        Card {
            Text("Import from a link").font(.headline)
            HStack(spacing: 10) {
                TextField("https://…", text: $link)
                    .textFieldStyle(.plain)
                    .focused($linkFocused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .submitLabel(.go)
                    .onSubmit(startDownload)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Button("Download", action: startDownload)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || importer.activity != nil)
            }
            Text("Paste a link to your own copy: a Google Drive file shared with \"Anyone with the link\", a Dropbox link, or any direct download.")
                .font(.subheadline)
                .opacity(0.85)
        }
    }

    private var inboxCard: some View {
        Card {
            Text("Or use the Firmware Inbox").font(.headline)
            #if os(iOS)
            Text("Put the files in Files › On My iPhone › \(AppConfig.displayName) › Firmware Inbox. They install automatically when you come back to the app.")
                .font(.subheadline)
                .opacity(0.85)
            #else
            Text("Put the files in the Firmware Inbox folder. They install automatically when you switch back to \(AppConfig.displayName).")
                .font(.subheadline)
                .opacity(0.85)
            Button("Show Firmware Inbox in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([FirmwareImporter.inbox])
            }
            .buttonStyle(.bordered)
            .tint(.white)
            #endif
        }
    }

    @ViewBuilder
    private var status: some View {
        if let activity = importer.activity {
            VStack(alignment: .leading, spacing: 8) {
                Text(activity).font(.callout.weight(.medium))
                if let progress = importer.progress {
                    ProgressView(value: progress).tint(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        if let notice = importer.notice {
            Card {
                Label(notice, systemImage: "info.circle")
                    .font(.callout)
                if importer.loneROM != nil {
                    Button("Install the ROM on its own") { importer.installLoneROM() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
        }
    }

    // MARK: Helpers

    private var platformDropHint: String {
        #if os(macOS)
        return ", or drag them onto this window"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? ", or drag them here" : ""
        #endif
    }

    private func startDownload() {
        linkFocused = false
        importer.importLink(link)
    }
}

/// A translucent panel on the wallpaper.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

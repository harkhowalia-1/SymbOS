// Halcyon - first-run setup: the user brings their own phone firmware.
//
// Nokia's firmware is copyrighted, so it is never bundled or downloaded by the app.
// Users dump it from a phone they own (ROM + RPKG via the "Dumber" tool).
//
// Licensed under the GNU General Public License v3 or later.

import SwiftUI

struct FirmwareSetupView: View {
    @EnvironmentObject private var controller: EmulatorController
    @State private var rom: URL?
    @State private var rpkg: URL?
    @State private var picking: Slot?

    enum Slot { case rom, rpkg }

    var body: some View {
        ZStack {
            Wallpaper()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set up your phone")
                            .font(.largeTitle.bold())
                        Text("\(AppConfig.displayName) runs the firmware from a Symbian phone you own. Dump it once from the phone, then add the two files here.")
                            .font(.body)
                            .opacity(0.9)
                    }

                    fileRow(title: "ROM", detail: "The phone's ROM image (for example SYM.ROM).", url: rom) { picking = .rom }
                    fileRow(title: "RPKG (recommended)", detail: "The repackaged Z: drive made with the Dumber tool.", url: rpkg) { picking = .rpkg }

                    Button {
                        if let rom { controller.installFirmware(rom: rom, rpkg: rpkg) }
                    } label: {
                        Text("Install firmware")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
                    .disabled(rom == nil)

                    Link(destination: AppConfig.guide("firmware")) {
                        Label("How to dump firmware from your phone", systemImage: "questionmark.circle")
                    }
                    .font(.callout)

                    Text("Firmware never leaves your device. \(AppConfig.displayName) does not include or download any Nokia software.")
                        .font(.footnote)
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                .padding(28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                      allowedContentTypes: SymbianFileTypes.firmware) { result in
            guard case .success(let url) = result else { return }
            switch picking {
            case .rom: rom = url
            case .rpkg: rpkg = url
            case nil: break
            }
            picking = nil
        }
    }

    private func fileRow(title: String, detail: String, url: URL?, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack(spacing: 14) {
                Image(systemName: url == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(url?.lastPathComponent ?? detail)
                        .font(.subheadline)
                        .opacity(0.8)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").opacity(0.6)
            }
            .padding(16)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

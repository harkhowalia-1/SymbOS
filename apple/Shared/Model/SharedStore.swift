// SymbOS - files shared between the app, its widgets and its App Intents.
//
// Lives in the App Group container:
//   apps.json            installed Symbian apps (uid + name)
//   layout.json          home screen pages and dock
//   icons/<UID>.png      app icons decoded from the firmware / packages
//
// Licensed under the GNU General Public License v3 or later.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum SharedStore {
    /// SideStore and AltStore re-sign with your own team and rename the App Group
    /// (typically to "group.<new bundle id>"), so try that form as well.
    static var groupCandidates: [String] {
        var ids = [AppConfig.appGroup]
        if var bundle = Bundle.main.bundleIdentifier {
            if Bundle.main.bundlePath.hasSuffix(".appex"), let dot = bundle.lastIndex(of: ".") {
                bundle = String(bundle[..<dot])   // the widget's id is <app id>.widgets
            }
            ids.append("group.\(bundle)")
        }
        return ids
    }

    static var container: URL {
        for id in groupCandidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        // No App Group (e.g. an unsigned build): keep working, widgets just won't see the data.
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SymbOSShared", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static var iconsDirectory: URL {
        let url = container.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Apps

    static func loadApps() -> [SymbianApp] {
        read([SymbianApp].self, from: "apps.json") ?? []
    }

    static func saveApps(_ apps: [SymbianApp]) {
        write(apps, to: "apps.json")
    }

    static func app(uid: UInt32) -> SymbianApp? {
        loadApps().first { $0.uid == uid }
    }

    // MARK: Layout

    static func loadLayout() -> HomeLayout? {
        read(HomeLayout.self, from: "layout.json")
    }

    static func saveLayout(_ layout: HomeLayout) {
        write(layout, to: "layout.json")
    }

    // MARK: Icons

    static func iconURL(uid: UInt32) -> URL {
        iconsDirectory.appendingPathComponent(String(format: "%08X.png", uid))
    }

    static func saveIcon(_ image: CGImage, uid: UInt32) {
        let url = iconURL(uid: uid)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    static func loadIcon(uid: UInt32) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(iconURL(uid: uid) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func iconPNGData(uid: UInt32) -> Data? {
        try? Data(contentsOf: iconURL(uid: uid))
    }

    // MARK: Helpers

    private static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: container.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: container.appendingPathComponent(name), options: .atomic)
    }
}

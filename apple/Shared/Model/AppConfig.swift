// Halcyon - build-time configuration read from Info.plist.
// Licensed under the GNU General Public License v3 or later.

import Foundation

enum AppConfig {
    /// Shared container used by the app, its widgets and its intents.
    static let appGroup: String = info("HalcyonAppGroup") ?? "group.io.github.halcyon"
    /// URL scheme for deep links, e.g. halcyon://launch?uid=0x101F4CD5
    static let urlScheme: String = info("HalcyonURLScheme") ?? "halcyon"
    /// Bundle identifier of the main app (also known inside the widget extension).
    static let appBundleID: String = info("HalcyonAppBundleID") ?? Bundle.main.bundleIdentifier ?? "io.github.halcyon"
    static let displayName: String = info("CFBundleDisplayName") ?? info("CFBundleName") ?? "Halcyon"
    static let version: String = info("CFBundleShortVersionString") ?? "0"
    static let repositoryURL = URL(string: info("HalcyonRepositoryURL") ?? "https://github.com")!
    static let websiteURL = URL(string: info("HalcyonWebsiteURL") ?? "https://github.com")!

    /// A section of the website's guide, e.g. guide("firmware").
    static func guide(_ section: String) -> URL {
        URL(string: websiteURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/guide.html#\(section)")!
    }

    private static func info(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}

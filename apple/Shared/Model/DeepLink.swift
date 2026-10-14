// Halcyon - the one deep link every shortcut, widget, web clip and Mac launcher uses.
//
//   halcyon://launch?uid=101F4CD5   open that Symbian app
//   halcyon://home                  show the home screen
//
// Licensed under the GNU General Public License v3 or later.

import Foundation

enum DeepLink: Equatable {
    case launch(uid: UInt32)
    case home

    init?(url: URL) {
        guard url.scheme?.lowercased() == AppConfig.urlScheme.lowercased() else { return nil }
        switch url.host?.lowercased() {
        case "launch":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let raw = items.first(where: { $0.name == "uid" })?.value,
                  let uid = SymbianApp.parseUID(raw) else { return nil }
            self = .launch(uid: uid)
        case "home", nil:
            self = .home
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .launch(let uid):
            return URL(string: "\(AppConfig.urlScheme)://launch?uid=\(String(format: "%08X", uid))")!
        case .home:
            return URL(string: "\(AppConfig.urlScheme)://home")!
        }
    }

    static func url(for app: SymbianApp) -> URL { DeepLink.launch(uid: app.uid).url }
}

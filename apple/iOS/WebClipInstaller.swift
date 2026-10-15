// SymbOS - real iPhone home screen icons for Symbian apps (sideloaded build).
//
// iOS gives apps no API to place an icon on the home screen. A configuration
// profile with a Web Clip payload can, and a web clip's URL may use a custom
// scheme, so the icon opens symbos://launch?uid=... directly.
//
// Profiles must be downloaded by Safari, so we serve the .mobileconfig from a
// one-shot web server on 127.0.0.1 for a few seconds and hand Safari its URL.
//
// Not used in an App Store build: guideline 5.5 holds apps that offer
// configuration profiles to its MDM requirements.
//
// Licensed under the GNU General Public License v3 or later.

import Foundation
import Network
import UIKit

@MainActor
final class WebClipInstaller {
    static let shared = WebClipInstaller()

    enum Failure: LocalizedError {
        case serverFailed
        var errorDescription: String? { "The local web server could not start." }
    }

    private var listener: NWListener?
    private var payload = Data()
    private var token = ""
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func install(app: SymbianApp, icon: CGImage?) throws {
        payload = try Self.profile(for: app, iconPNG: Self.homeScreenIconPNG(from: icon))
        token = UUID().uuidString
        try startServer()
    }

    // MARK: Profile

    static func profile(for app: SymbianApp, iconPNG: Data?) throws -> Data {
        let base = AppConfig.appBundleID
        var clip: [String: Any] = [
            "PayloadType": "com.apple.webClip.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": "\(base).webclip.\(app.uidHex)",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": app.name,
            "Label": app.name,
            "URL": DeepLink.url(for: app).absoluteString,
            "IsRemovable": true,
            "FullScreen": false,
            "Precomposed": true,
        ]
        if let iconPNG {
            clip["Icon"] = iconPNG
        }
        let profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "\(base).shortcut.\(app.uidHex)",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "\(app.name) (\(AppConfig.displayName))",
            "PayloadDescription": "Adds a Home Screen icon that opens \(app.name) in \(AppConfig.displayName).",
            "PayloadRemovalDisallowed": false,
            "PayloadContent": [clip],
        ]
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }

    /// 180x180 icon: the Symbian icon centred on a light tile, like the in-app home screen.
    static func homeScreenIconPNG(from icon: CGImage?) -> Data? {
        let size = CGSize(width: 180, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return format
        }())
        let image = renderer.image { context in
            let colors = [UIColor.white.cgColor, UIColor(white: 0.9, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            if let icon {
                let inset: CGFloat = 22
                let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
                UIImage(cgImage: icon).draw(in: rect)
            }
        }
        return image.pngData()
    }

    // MARK: One-shot web server

    private func startServer() throws {
        stopServer()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: parameters) else { throw Failure.serverFailed }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.serve(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener?.port?.rawValue,
                          let url = URL(string: "http://127.0.0.1:\(port)/\(self.token).mobileconfig") else { return }
                    // Keep serving while Safari is in front.
                    self.backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                        Task { @MainActor in self?.stopServer() }
                    }
                    UIApplication.shared.open(url)
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(25))
                        self?.stopServer()
                    }
                case .failed:
                    self.stopServer()
                default:
                    break
                }
            }
        }
        listener.start(queue: .main)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let wanted = request.hasPrefix("GET /\(self.token).mobileconfig")
                let body = wanted ? self.payload : Data("Not found".utf8)
                var head = wanted ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 404 Not Found\r\n"
                head += "Content-Type: \(wanted ? "application/x-apple-aspen-config" : "text/plain")\r\n"
                head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func stopServer() {
        listener?.cancel()
        listener = nil
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}

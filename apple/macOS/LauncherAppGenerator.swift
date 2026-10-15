// SymbOS - Parallels-style launcher apps for Symbian apps (Mac direct build).
//
// Creates ~/Applications/<App Name> Apps/<Symbian app>.app: a tiny bundle whose
// executable is a shell script that opens symbos://launch?uid=..., with the
// Symbian icon converted to .icns. Launchpad, Spotlight and the Dock treat it like
// any other app. Each bundle is signed ad hoc on this Mac; files we write are not
// quarantined, so Gatekeeper lets them run.
//
// The Mac App Store forbids this (guideline 2.4.5), so it only ships in the direct build.
//
// Licensed under the GNU General Public License v3 or later.

import AppKit
import CoreServices
import ImageIO
import UniformTypeIdentifiers

enum LauncherAppGenerator {
    enum Failure: LocalizedError {
        case signing(String)
        var errorDescription: String? {
            switch self {
            case .signing(let output): return "Signing failed: \(output)"
            }
        }
    }

    static var folder: URL {
        let applications = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)[0]
        return applications.appendingPathComponent("\(AppConfig.displayName) Apps", isDirectory: true)
    }

    @discardableResult
    static func create(for app: SymbianApp, icon: CGImage?) throws -> URL {
        let fm = FileManager.default
        let safeName = app.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let bundle = folder.appendingPathComponent("\(safeName).app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)

        if fm.fileExists(atPath: bundle.path) {
            try fm.removeItem(at: bundle)
        }
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "launch",
            "CFBundleIdentifier": "\(AppConfig.appBundleID).launcher.\(app.uidHex)",
            "CFBundleName": app.name,
            "CFBundleDisplayName": app.name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleIconFile": "AppIcon",
            "LSMinimumSystemVersion": "13.0",
            "LSUIElement": true,
            "NSHumanReadableCopyright": "Opens \(app.name) in \(AppConfig.displayName).",
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let script = """
        #!/bin/sh
        # Opens \(app.name) (UID \(app.uidHex)) in \(AppConfig.displayName).
        exec /usr/bin/open "\(DeepLink.url(for: app).absoluteString)"

        """
        let executable = macOS.appendingPathComponent("launch")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        if let icon {
            writeICNS(icon, to: resources.appendingPathComponent("AppIcon.icns"))
        }

        try sign(bundle)
        LSRegisterURL(bundle as CFURL, true)
        return bundle
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Render the Symbian icon onto a rounded light tile at each size an .icns needs.
    private static func writeICNS(_ icon: CGImage, to url: URL) {
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.icns.identifier as CFString, sizes.count, nil) else { return }
        for size in sizes {
            if let tile = tileImage(icon, size: size) {
                CGImageDestinationAddImage(dest, tile, nil)
            }
        }
        CGImageDestinationFinalize(dest)
    }

    private static func tileImage(_ icon: CGImage, size: Int) -> CGImage? {
        let s = CGFloat(size)
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // macOS icon grid: the tile fills about 80% of the canvas.
        let tile = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
        let path = CGPath(roundedRect: tile, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fillPath()
        ctx.interpolationQuality = .high
        ctx.draw(icon, in: tile.insetBy(dx: s * 0.1, dy: s * 0.1))
        return ctx.makeImage()
    }

    private static func sign(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", bundle.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure.signing(output)
        }
    }
}

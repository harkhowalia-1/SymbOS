// Halcyon - getting the user's own firmware into the app with as little effort as possible.
//
// Every route ends in the Firmware Inbox folder, which is then processed the same way:
//
//   * Choose files / drag and drop / "Open in Halcyon" (ROM, RPKG, VPL or a .zip of them)
//   * Import from link: a URL to the user's own copy (Google Drive, Dropbox or direct)
//   * Files the user puts in the inbox themselves (Files app on iPhone, Finder on Mac),
//     picked up automatically whenever the app becomes active
//
// Processing: unzip archives, pair a ROM with its RPKG (or use a VPL set), install, then
// move what was used into "Firmware Inbox/Installed" so it isn't installed twice.
// Halcyon never ships or fetches firmware on its own; links always come from the user.
//
// Licensed under the GNU General Public License v3 or later.

import Foundation
import SwiftUI

@MainActor
final class FirmwareImporter: ObservableObject {
    static let shared = FirmwareImporter()

    /// What the importer is doing right now (shown on the setup screen).
    @Published private(set) var activity: String?
    /// 0...1 while downloading or unzipping.
    @Published private(set) var progress: Double?
    /// A problem or a missing half of a pair, with a way forward.
    @Published private(set) var notice: String?
    /// A ROM with no RPKG was found; the user may install it on its own.
    @Published private(set) var loneROM: URL?

    private var busy = false
    /// Files that failed to install this session, so they aren't retried on every activation.
    private var failedPaths: Set<String> = []
    private let queue = DispatchQueue(label: "halcyon.firmware-import", qos: .userInitiated)

    // MARK: Folders

    /// The folder users can drop firmware into. On iPhone it is visible in the Files app
    /// (On My iPhone › Halcyon › Firmware Inbox).
    nonisolated static var inbox: URL {
        #if os(iOS)
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Halcyon", isDirectory: true)
        #endif
        let url = base.appendingPathComponent("Firmware Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let readme = url.appendingPathComponent("Put your ROM and RPKG here.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            let text = """
            Put the firmware from your own Symbian phone in this folder: the ROM (for example SYM.ROM) \
            and its .rpkg file, or a .zip that contains them. Halcyon installs them the next time it opens \
            and then moves them to the Installed folder, which you can delete afterwards.
            """
            try? text.write(to: readme, atomically: true, encoding: .utf8)
        }
        return url
    }

    nonisolated static var installedFolder: URL {
        inbox.appendingPathComponent("Installed", isDirectory: true)
    }

    // MARK: Entry points

    /// Files chosen in the picker, dropped on the window, or opened with "Open in Halcyon".
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        notice = nil
        activity = "Copying firmware…"
        queue.async {
            var failures: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let target = Self.uniqueURL(in: Self.inbox, name: url.lastPathComponent)
                do {
                    // Files handed to us in the app's Inbox (Open in…) can simply be moved.
                    if url.path.contains("/Inbox/") {
                        try FileManager.default.moveItem(at: url, to: target)
                    } else {
                        try FileManager.default.copyItem(at: url, to: target)
                    }
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }
            let failed = failures
            Task { @MainActor in
                self.activity = nil
                if !failed.isEmpty {
                    self.notice = "Couldn't read \(failed.joined(separator: ", "))."
                }
                self.processInbox()
            }
        }
    }

    /// Download the user's own firmware from a link they paste.
    func importLink(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
            notice = "That doesn't look like a web link. Paste a link that starts with https://."
            return
        }
        notice = nil
        activity = "Downloading…"
        progress = 0
        Task {
            do {
                let file = try await LinkDownloader.download(url) { fraction in
                    Task { @MainActor in self.progress = fraction }
                }
                let target = Self.uniqueURL(in: Self.inbox, name: file.lastPathComponent)
                try FileManager.default.moveItem(at: file, to: target)
                activity = nil
                progress = nil
                processInbox()
            } catch {
                activity = nil
                progress = nil
                notice = error.localizedDescription
            }
        }
    }

    /// Install a ROM that has no RPKG next to it (older firmware or a full ROM dump).
    func installLoneROM() {
        guard let rom = loneROM else { return }
        loneROM = nil
        install(rom: rom, rpkg: nil, others: [])
    }

    // MARK: Processing

    /// Look in the inbox and install anything usable. Safe to call often (on every
    /// launch and every time the app becomes active).
    func processInbox() {
        // Installing needs the emulator to have finished booting (with or without firmware).
        let phase = EmulatorController.shared.phase
        guard phase == .ready || phase == .needsFirmware else { return }
        guard !busy, activity == nil else { return }
        busy = true
        let skip = failedPaths
        queue.async {
            let outcome = Self.scan(skipping: skip)
            Task { @MainActor in
                self.busy = false
                self.handle(outcome)
            }
        }
    }

    private enum Outcome {
        case nothing
        case pair(rom: URL, rpkg: URL?, others: [URL])
        case loneROM(URL)
        case loneRPKG(URL)
        case failed(String)
    }

    private func handle(_ outcome: Outcome) {
        switch outcome {
        case .nothing:
            break
        case .pair(let rom, let rpkg, let others):
            install(rom: rom, rpkg: rpkg, others: others)
        case .loneROM(let rom):
            loneROM = rom
            notice = "Found \(rom.lastPathComponent). Belle and Symbian^3 phones also need the .rpkg file from the same phone; add it to finish, or install the ROM on its own."
        case .loneRPKG(let rpkg):
            loneROM = nil
            notice = "Found \(rpkg.lastPathComponent). Add the ROM from the same phone (for example SYM.ROM) to finish."
        case .failed(let message):
            notice = message
        }
    }

    private func install(rom: URL, rpkg: URL?, others: [URL]) {
        activity = "Installing firmware…"
        notice = nil
        EmulatorController.shared.installFirmware(rom: rom, rpkg: rpkg, alreadyLocal: true) { succeeded, message in
            self.activity = nil
            if succeeded {
                self.loneROM = nil
                Self.archive([rom] + [rpkg].compactMap { $0 } + others)
            } else {
                self.failedPaths.insert(rom.resolvingSymlinksInPath().path)
                self.notice = message ?? "The firmware could not be installed."
            }
        }
    }

    /// Runs on the import queue.
    nonisolated private static func scan(skipping skip: Set<String>) -> Outcome {
        let fm = FileManager.default
        let inbox = Self.inbox

        // 1. Unzip archives into a folder of the same name, then archive the zip.
        let topLevel = (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        for zip in topLevel where zip.pathExtension.lowercased() == "zip" {
            let folder = uniqueURL(in: inbox, name: zip.deletingPathExtension().lastPathComponent)
            do {
                try ZipExtractor.extract(zip, to: folder)
                archive([zip])
            } catch {
                archive([zip])
                return .failed("\(zip.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // 2. Find candidates anywhere in the inbox except the Installed folder.
        var roms: [URL] = []
        var rpkgs: [URL] = []
        var vpls: [URL] = []
        // Compare resolved paths: on iPhone the same folder can appear as /var/... or /private/var/...
        let installed = installedFolder.resolvingSymlinksInPath().path
        if let walker = fm.enumerator(at: inbox, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in walker {
                let path = url.resolvingSymlinksInPath().path
                if path.hasPrefix(installed) {
                    walker.skipDescendants()
                    continue
                }
                if skip.contains(path) { continue }
                switch url.pathExtension.lowercased() {
                case "rom": roms.append(url)
                case "rpkg": rpkgs.append(url)
                case "vpl": vpls.append(url)
                default: break
                }
            }
        }

        // 3. Decide what to install.
        if let vpl = vpls.first {
            // A VPL manifest needs its .fpsx/.rofs files in the same folder; archive the folder.
            return .pair(rom: vpl, rpkg: nil, others: siblings(of: vpl))
        }
        if let rom = roms.first {
            // Prefer an RPKG from the same folder, otherwise any RPKG.
            let rpkg = rpkgs.first { $0.deletingLastPathComponent() == rom.deletingLastPathComponent() } ?? rpkgs.first
            if let rpkg {
                return .pair(rom: rom, rpkg: rpkg, others: [])
            }
            return .loneROM(rom)
        }
        if let rpkg = rpkgs.first {
            return .loneRPKG(rpkg)
        }
        return .nothing
    }

    // MARK: Helpers

    nonisolated private static func siblings(of url: URL) -> [URL] {
        let folder = url.deletingLastPathComponent()
        return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0 != url }
    }

    /// Move used files (and folders left empty by them) into Firmware Inbox/Installed.
    nonisolated private static func archive(_ urls: [URL]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: installedFolder, withIntermediateDirectories: true)
        for url in urls where fm.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            try? fm.moveItem(at: url, to: uniqueURL(in: installedFolder, name: url.lastPathComponent))
            if parent.resolvingSymlinksInPath().path != inbox.resolvingSymlinksInPath().path,
               let left = try? fm.contentsOfDirectory(atPath: parent.path), left.isEmpty {
                try? fm.removeItem(at: parent)
            }
        }
    }

    nonisolated static func uniqueURL(in folder: URL, name: String) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    /// File types the app accepts as firmware ("Open in Halcyon", drag and drop).
    nonisolated static func isFirmwareFile(_ url: URL) -> Bool {
        ["rom", "rpkg", "vpl", "zip"].contains(url.pathExtension.lowercased())
    }
}

// MARK: - Downloading from a user-supplied link

enum LinkDownloader {
    enum Failure: LocalizedError {
        case notAFile
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notAFile:
                return "The link opened a web page instead of a file. For Google Drive, set sharing to \"Anyone with the link\"; for other sites, use the direct download link."
            case .http(let code):
                return "The download failed (HTTP \(code)). Check that the link is shared publicly."
            }
        }
    }

    /// Turn share links into direct-download links where the service allows it.
    static func directURL(for url: URL) -> URL {
        guard let host = url.host?.lowercased() else { return url }

        if host == "drive.google.com" || host == "docs.google.com" {
            // https://drive.google.com/file/d/<ID>/view?usp=sharing  or  ...?id=<ID>
            var id: String?
            let parts = url.pathComponents
            if let i = parts.firstIndex(of: "d"), i + 1 < parts.count { id = parts[i + 1] }
            if id == nil {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
            }
            if let id {
                // confirm=t skips Drive's "can't scan this large file for viruses" page.
                return URL(string: "https://drive.usercontent.google.com/download?id=\(id)&export=download&confirm=t")!
            }
        }

        if host.hasSuffix("dropbox.com"), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = (components.queryItems ?? []).filter { $0.name != "dl" }
            items.append(URLQueryItem(name: "dl", value: "1"))
            components.queryItems = items
            return components.url ?? url
        }

        return url
    }

    /// Download to a temporary file named after the server's file name.
    static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let direct = directURL(for: url)
        let (file, response) = try await downloadFile(direct, progress: progress)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }
        // A web page instead of a file: Drive's warning page, a login page, a viewer.
        if (response.mimeType ?? "").hasPrefix("text/html") || looksLikeHTML(file) {
            try? FileManager.default.removeItem(at: file)
            throw Failure.notAFile
        }

        let name = response.suggestedFilename.flatMap { $0.isEmpty ? nil : $0 } ?? direct.lastPathComponent
        let named = file.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: named.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: file, to: named)
        return named
    }

    private static func downloadFile(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let observation = ObservationBox()
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                observation.value?.invalidate()
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let location, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                // The system deletes `location` when this handler returns; keep it.
                let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: location, to: keep)
                    continuation.resume(returning: (keep, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            observation.value = task.progress.observe(\.fractionCompleted) { value, _ in
                progress(value.fractionCompleted)
            }
            task.resume()
        }
    }

    private static func looksLikeHTML(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file),
              let head = try? handle.read(upToCount: 512) else { return false }
        try? handle.close()
        let text = String(decoding: head, as: UTF8.self).lowercased()
        return text.contains("<!doctype html") || text.contains("<html")
    }
}

/// Holds the progress observation so the download's completion handler can end it.
private final class ObservationBox: @unchecked Sendable {
    var value: NSKeyValueObservation?
}

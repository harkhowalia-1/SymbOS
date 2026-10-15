// SymbOS - owns the emulated phone: boot, app list, installs, launching, dialogs.
// Licensed under the GNU General Public License v3 or later.

import Foundation
import SwiftUI
import CoreGraphics

@MainActor
final class EmulatorController: ObservableObject {
    static let shared = EmulatorController()

    enum Phase: Equatable {
        case waitingForSurface
        case booting
        case needsFirmware
        case ready
        case failed(String)
    }

    struct TextRequest: Identifiable {
        let id = UUID()
        var text: String
        let maxLength: Int
    }

    struct QuestionRequest: Identifiable {
        let id = UUID()
        let message: String
        let firstButton: String
        let secondButton: String
    }

    struct InstallResult: Identifiable {
        let id = UUID()
        let fileName: String
        let succeeded: Bool
        let message: String
        let newApps: [SymbianApp]
    }

    @Published private(set) var phase: Phase = .waitingForSurface
    @Published private(set) var apps: [SymbianApp] = []
    @Published private(set) var runningApp: SymbianApp?
    /// The running app is on screen (otherwise the home screen is).
    @Published var isShowingApp = false
    @Published private(set) var busyMessage: String?
    @Published var layout = HomeLayout()
    @Published var textRequest: TextRequest?
    @Published var questionRequest: QuestionRequest?
    @Published var installResult: InstallResult?
    @Published private(set) var usingJIT = false
    @Published private(set) var fps: Float?
    /// Bumped by the Mac's File › Install App… command; the home screen opens its file picker.
    @Published private(set) var importRequests = 0

    let emulator = HCEmulator.shared
    /// The single surface the core renders into; screens move it around instead of recreating it.
    let surfaceView = HCEmulatorView(frame: CGRect(x: 0, y: 0, width: 360, height: 640))

    private var pendingLaunch: UInt32?
    private var iconImages: [UInt32: CGImage] = [:]
    private var fpsTimer: Timer?
    private let work = DispatchQueue(label: "symbos.emulator", qos: .userInitiated)

    var isMock: Bool { emulator.isMock }

    var dataDirectory: URL {
        #if os(iOS)
        // Documents is visible in the Files app, so users can reach the E: drive.
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        return base.appendingPathComponent("SymbOS", isDirectory: true)
    }

    private init() {
        layout = SharedStore.loadLayout() ?? HomeLayout()
        apps = SharedStore.loadApps()

        surfaceView.readyHandler = { [weak self] _ in
            Task { @MainActor in self?.boot() }
        }
        // HCEmulator delivers these on the main queue.
        emulator.appExitHandler = { [weak self] in
            MainActor.assumeIsolated {
                self?.runningApp = nil
                self?.isShowingApp = false
            }
        }
        emulator.textInputHandler = { [weak self] initial, maxLength in
            MainActor.assumeIsolated {
                self?.textRequest = TextRequest(text: initial, maxLength: maxLength)
            }
        }
        emulator.questionHandler = { [weak self] message, first, second in
            MainActor.assumeIsolated {
                self?.questionRequest = QuestionRequest(message: message, firstButton: first, secondButton: second)
            }
        }
    }

    // MARK: Boot

    private func boot() {
        guard phase == .waitingForSurface else { return }
        phase = .booting
        let dataDir = dataDirectory
        let bundle = Bundle.main.resourcePath ?? ""
        let surface = surfaceView.renderSurface
        let width = surfaceView.drawableWidth
        let height = surfaceView.drawableHeight
        usingJIT = JITSupport.willUseJIT

        work.async { [emulator] in
            try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            JITSupport.applyToCoreConfig(dataDirectory: dataDir)
            emulator.prepareDataDirectory(dataDir.path, bundleResources: bundle)
            let booted = emulator.start(withSurface: surface, width: Int32(width), height: Int32(height))
            Task { @MainActor in
                self.phase = booted ? .ready : .needsFirmware
                if booted {
                    self.applyDeviceSettings()
                    self.refreshApps()
                    self.startFPSSampling()
                    if let uid = self.pendingLaunch {
                        self.pendingLaunch = nil
                        self.launch(uid: uid)
                    }
                }
                // Install firmware waiting in the Firmware Inbox (works with or without a device).
                FirmwareImporter.shared.processInbox()
            }
        }
    }

    private func applyDeviceSettings() {
        let defaults = UserDefaults.standard
        emulator.setGyroPassthrough(defaults.object(forKey: "gyroPassthrough") as? Bool ?? true)
        emulator.setHapticPassthrough(defaults.object(forKey: "hapticPassthrough") as? Bool ?? true)
    }

    // MARK: Apps

    func refreshApps() {
        let list = emulator.apps().map { SymbianApp(uid: $0.uid, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for app in list where iconImages[app.uid] == nil {
            if let image = emulator.copyIcon(forUID: app.uid) {
                iconImages[app.uid] = image
                SharedStore.saveIcon(image, uid: app.uid)
            }
        }
        apps = list
        layout.reconcile(with: list)
        SharedStore.saveApps(list)
        SharedStore.saveLayout(layout)
        SpotlightIndexer.update(apps: list)
    }

    func app(uid: UInt32) -> SymbianApp? { apps.first { $0.uid == uid } }

    func icon(for uid: UInt32) -> CGImage? {
        if let image = iconImages[uid] { return image }
        if let image = SharedStore.loadIcon(uid: uid) {
            iconImages[uid] = image
            return image
        }
        return nil
    }

    func saveLayout() {
        SharedStore.saveLayout(layout)
    }

    // MARK: Launching

    func handle(_ link: DeepLink) {
        switch link {
        case .home:
            goHome()
        case .launch(let uid):
            if phase == .ready {
                launch(uid: uid)
            } else {
                pendingLaunch = uid
            }
        }
    }

    func launch(uid: UInt32) {
        let target = app(uid: uid) ?? SymbianApp(uid: uid, name: "App")
        if runningApp?.uid == uid {
            emulator.resume()
            isShowingApp = true
            return
        }
        if runningApp != nil {
            // The core runs one app at a time: close the current one (reboots the guest).
            busyMessage = "Opening \(target.name)…"
            work.async { [emulator] in
                emulator.exitApp()
                Task { @MainActor in
                    self.busyMessage = nil
                    self.start(target)
                }
            }
        } else {
            start(target)
        }
    }

    private func start(_ app: SymbianApp) {
        emulator.resume()
        emulator.launchApp(withUID: app.uid)
        runningApp = app
        isShowingApp = true
    }

    /// Back to the home screen; the app stays in memory, paused.
    func goHome() {
        guard isShowingApp else { return }
        isShowingApp = false
        if !UserDefaults.standard.bool(forKey: "fullSymbianMode") {
            emulator.pause()
        }
    }

    /// Quit the running app (reboots the guest in the background).
    func closeRunningApp() {
        guard runningApp != nil else { return }
        isShowingApp = false
        runningApp = nil
        busyMessage = "Closing app…"
        work.async { [emulator] in
            emulator.exitApp()
            Task { @MainActor in self.busyMessage = nil }
        }
    }

    func requestImport() {
        goHome()
        importRequests += 1
    }

    func press(_ key: HCKey) {
        emulator.tap(key)
    }

    // MARK: Lifecycle

    func appDidEnterBackground() {
        if phase == .ready { emulator.pause() }
    }

    func appDidBecomeActive() {
        if phase == .ready, isShowingApp || UserDefaults.standard.bool(forKey: "fullSymbianMode") {
            emulator.resume()
        }
        // The user may have dropped firmware into the inbox from the Files app or Finder.
        FirmwareImporter.shared.processInbox()
    }

    // MARK: Installing apps

    /// Install .sis/.sisx files picked by the user (security-scoped URLs).
    func install(packages urls: [URL]) {
        guard let url = urls.first else { return }
        let remaining = Array(urls.dropFirst())
        let name = url.lastPathComponent
        busyMessage = "Installing \(name)…"
        let before = Set(apps.map(\.uid))

        work.async { [emulator] in
            let local = Self.copyToTemporary(url)
            let code = local.map { emulator.installPackage(atPath: $0.path) } ?? -1
            if let local { try? FileManager.default.removeItem(at: local) }
            Task { @MainActor in
                self.busyMessage = nil
                self.refreshApps()
                let added = self.apps.filter { !before.contains($0.uid) }
                let message: String
                switch code {
                case 0: message = added.isEmpty ? "Installed. It may add a component rather than a new icon." : "Installed."
                case 1: message = "The installation was cancelled."
                case 2: message = "This file is not a valid Symbian package for this phone."
                default: message = "The emulator is not ready yet. Install firmware first."
                }
                self.installResult = InstallResult(fileName: name, succeeded: code == 0, message: message, newApps: added)
                if !remaining.isEmpty { self.install(packages: remaining) }
            }
        }
    }

    func uninstall(_ app: SymbianApp) {
        guard let package = emulator.packages().first(where: { $0.uid == app.uid }) else {
            installResult = InstallResult(fileName: app.name, succeeded: false,
                                          message: "\(app.name) is part of the firmware and can't be removed. You can hide it instead.",
                                          newApps: [])
            return
        }
        if runningApp?.uid == app.uid {
            runningApp = nil
            isShowingApp = false
        }
        busyMessage = "Removing \(app.name)…"
        work.async { [emulator] in
            emulator.uninstallPackageUID(package.uid, index: package.index)
            Task { @MainActor in
                self.busyMessage = nil
                self.layout.remove(app.uid)
                self.refreshApps()
            }
        }
    }

    // MARK: Firmware

    /// Install firmware. `alreadyLocal` skips the temporary copy for files that are
    /// already inside the app's container (the Firmware Inbox), which matters for
    /// RPKGs of several hundred MB. `completion` gets (succeeded, error message);
    /// "already installed" counts as success.
    func installFirmware(rom: URL, rpkg: URL?, alreadyLocal: Bool = false,
                         completion: (@MainActor (Bool, String?) -> Void)? = nil) {
        busyMessage = "Installing firmware…"
        work.async { [emulator] in
            let localROM = alreadyLocal ? rom : Self.copyToTemporary(rom)
            let localRPKG = alreadyLocal ? rpkg : rpkg.flatMap(Self.copyToTemporary)
            var code: Int32 = -1
            if let localROM {
                code = emulator.installDeviceROM(localROM.path, rpkg: localRPKG?.path) { percent in
                    Task { @MainActor in self.busyMessage = "Installing firmware… \(percent)%" }
                }
            }
            if !alreadyLocal {
                [localROM, localRPKG].compactMap { $0 }.forEach { try? FileManager.default.removeItem(at: $0) }
            }
            let result = code
            let hasDevice = emulator.hasDevice
            Task { @MainActor in
                self.busyMessage = nil
                if result == 0 || (result == 5 && hasDevice) {
                    self.phase = .ready
                    self.applyDeviceSettings()
                    self.refreshApps()
                    self.startFPSSampling()
                    completion?(true, nil)
                } else {
                    if !hasDevice { self.phase = .needsFirmware }
                    let message = Self.firmwareError(result)
                    if let completion {
                        completion(false, message)
                    } else {
                        self.installResult = InstallResult(fileName: rom.lastPathComponent, succeeded: false,
                                                           message: message, newApps: [])
                    }
                }
            }
        }
    }

    private static func firmwareError(_ code: Int32) -> String {
        switch code {
        case 1: return "The ROM file could not be found."
        case 2: return "There isn't enough free space to unpack the firmware."
        case 3: return "The RPKG file is damaged."
        case 4: return "The phone model in this dump could not be identified."
        case 5: return "This firmware is already installed."
        case 7: return "The ROM could not be copied."
        case 10: return "The ROM file is damaged."
        default: return "The firmware could not be installed (error \(code))."
        }
    }

    // MARK: Settings that reboot

    func setJIT(_ enabled: Bool) {
        JITSupport.userWantsJIT = enabled
        let effective = JITSupport.willUseJIT
        guard effective != usingJIT, phase == .ready else { return }
        usingJIT = effective
        runningApp = nil
        isShowingApp = false
        busyMessage = effective ? "Restarting with JIT…" : "Restarting without JIT…"
        work.async { [emulator] in
            emulator.jitEnabled = effective
            Task { @MainActor in
                self.busyMessage = nil
                self.refreshApps()
            }
        }
    }

    // MARK: Dialogs

    func answerText(_ text: String?) {
        let fallback = textRequest?.text ?? ""
        textRequest = nil
        emulator.finishTextInput(text ?? fallback)
    }

    func answerQuestion(first: Bool) {
        questionRequest = nil
        emulator.finishQuestion(first)
    }

    // MARK: Helpers

    private func startFPSSampling() {
        fpsTimer?.invalidate()
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var value: Float = 0
                self.fps = self.emulator.sampleFPS(&value) ? value : nil
            }
        }
    }

    /// The core needs a plain path it can read on its own thread.
    nonisolated private static func copyToTemporary(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let target = destination.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }
}

// SymbOS - deciding between the Dynarmic JIT and the dyncom interpreter.
//
// The core reads its CPU backend from config.yml ("ios-enable-jit") at boot. Booting
// the JIT without permission to map executable memory crashes, so the choice is
// written to config.yml *before* every boot, from what this process can actually do:
//
//   macOS            always (Hardened Runtime + com.apple.security.cs.allow-jit)
//   iOS sideload     only when a debugger attached at launch (StikDebug), detected
//                    through the CS_DEBUGGED code-signing flag
//
// Licensed under the GNU General Public License v3 or later.

import Foundation
#if os(iOS)
import UIKit
#endif

enum JITSupport {
    private static let preferenceKey = "useJIT"

    /// The user's choice; JIT is used when this is on and the process allows it.
    static var userWantsJIT: Bool {
        get { UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    static var isAvailable: Bool {
        #if os(macOS)
        return true
        #else
        return isDebuggerAttached
        #endif
    }

    static var willUseJIT: Bool { userWantsJIT && isAvailable }

    #if os(iOS)
    /// CS_DEBUGGED (0x10000000) is set once a debugger has attached, which is what
    /// StikDebug does to grant JIT to sideloaded apps.
    static var isDebuggerAttached: Bool {
        var flags: UInt32 = 0
        let result = symbos_csops(getpid(), 0 /* CS_OPS_STATUS */, &flags, MemoryLayout<UInt32>.size)
        return result == 0 && (flags & 0x1000_0000) != 0
    }

    /// Ask StikDebug to attach and relaunch this app with JIT.
    @MainActor
    static func requestJITFromStikDebug() {
        let id = AppConfig.appBundleID
        let candidates = [
            "stikjit://enable-jit?bundle-id=\(id)",
            "stikdebug://enable-jit?bundle-id=\(id)",
        ]
        Task {
            for string in candidates {
                guard let url = URL(string: string) else { continue }
                if await UIApplication.shared.open(url) { return }
            }
        }
    }
    #endif

    /// Write the backend choice into the core's config before it boots.
    static func applyToCoreConfig(dataDirectory: URL) {
        let url = dataDirectory.appendingPathComponent("config.yml")
        let value = willUseJIT ? "true" : "false"
        let line = "ios-enable-jit: \(value)"
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if let index = lines.firstIndex(where: { $0.hasPrefix("ios-enable-jit:") }) {
            lines[index] = line
        } else {
            if lines.last == "" { lines.removeLast() }
            lines.append(line)
            lines.append("")
        }
        text = lines.joined(separator: "\n")
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

#if os(iOS)
/// csops(2) is not in the public SDK headers; it is a stable syscall wrapper in libsystem.
@_silgen_name("csops")
private func symbos_csops(_ pid: pid_t, _ ops: UInt32, _ useraddr: UnsafeMutableRawPointer?, _ usersize: Int) -> Int32
#endif

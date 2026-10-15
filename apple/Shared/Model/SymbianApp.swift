// SymbOS - an app registered in the emulated phone.
// Licensed under the GNU General Public License v3 or later.

import Foundation

struct SymbianApp: Codable, Hashable, Identifiable, Sendable {
    /// Symbian application UID (unique per app).
    let uid: UInt32
    var name: String

    var id: UInt32 { uid }

    /// "101F4CD5" - used in file names and deep links.
    var uidHex: String { String(format: "%08X", uid) }

    init(uid: UInt32, name: String) {
        self.uid = uid
        self.name = name
    }

    static func parseUID(_ text: String) -> UInt32? {
        var s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        return UInt32(s, radix: 16)
    }
}

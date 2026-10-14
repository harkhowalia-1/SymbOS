// Halcyon - where each icon sits on the home screen.
// Licensed under the GNU General Public License v3 or later.

import Foundation

struct HomeLayout: Codable, Equatable, Sendable {
    /// Icons per page, in reading order.
    var pages: [[UInt32]] = [[]]
    /// Up to `dockCapacity` icons pinned to the dock.
    var dock: [UInt32] = []
    /// Apps the user hid from the home screen (still installed, still launchable).
    var hidden: [UInt32] = []

    static let pageCapacity = 24   // 4 columns x 6 rows
    static let dockCapacity = 4

    /// Apps a Belle home screen keeps in the dock, matched by name in the user's firmware.
    private static let preferredDock = ["Messaging", "Web", "Music", "Contacts"]

    var allUIDs: Set<UInt32> { Set(pages.flatMap { $0 } + dock + hidden) }

    /// Drop apps that were uninstalled and place new ones in the first free slot.
    mutating func reconcile(with apps: [SymbianApp]) {
        let installed = Set(apps.map(\.uid))
        pages = pages.map { $0.filter(installed.contains) }
        dock = dock.filter(installed.contains)
        hidden = hidden.filter(installed.contains)

        if dock.isEmpty && pages.allSatisfy({ $0.isEmpty }) {
            for name in Self.preferredDock {
                if let match = apps.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    dock.append(match.uid)
                }
            }
        }

        let placed = allUIDs
        for app in apps where !placed.contains(app.uid) {
            place(app.uid)
        }
        pages.removeAll { $0.isEmpty }
        if pages.isEmpty { pages = [[]] }
    }

    mutating func place(_ uid: UInt32) {
        if let index = pages.firstIndex(where: { $0.count < Self.pageCapacity }) {
            pages[index].append(uid)
        } else {
            pages.append([uid])
        }
    }

    mutating func hide(_ uid: UInt32) {
        remove(uid)
        hidden.append(uid)
    }

    mutating func unhide(_ uid: UInt32) {
        hidden.removeAll { $0 == uid }
        place(uid)
    }

    /// Takes an icon off the pages and dock (it is placed again on the next reconcile
    /// unless it was hidden or uninstalled).
    mutating func remove(_ uid: UInt32) {
        pages = pages.map { $0.filter { $0 != uid } }
        dock.removeAll { $0 == uid }
        hidden.removeAll { $0 == uid }
    }

    /// Move `uid` so it sits just before `target` (on whichever page or dock target is on).
    mutating func move(_ uid: UInt32, before target: UInt32) {
        guard uid != target else { return }
        remove(uid)
        if let index = dock.firstIndex(of: target), dock.count < Self.dockCapacity {
            dock.insert(uid, at: index)
            return
        }
        for p in pages.indices {
            if let index = pages[p].firstIndex(of: target) {
                pages[p].insert(uid, at: index)
                overflow(from: p)
                return
            }
        }
        place(uid)
    }

    mutating func moveToDock(_ uid: UInt32) {
        guard !dock.contains(uid), dock.count < Self.dockCapacity else { return }
        remove(uid)
        dock.append(uid)
    }

    mutating func moveToPage(_ uid: UInt32, page: Int) {
        remove(uid)
        while pages.count <= page { pages.append([]) }
        pages[page].append(uid)
        overflow(from: page)
    }

    /// Push icons beyond a page's capacity onto the next page.
    private mutating func overflow(from page: Int) {
        var p = page
        while p < pages.count, pages[p].count > Self.pageCapacity {
            let extra = pages[p].removeLast()
            if p + 1 == pages.count { pages.append([]) }
            pages[p + 1].insert(extra, at: 0)
            p += 1
        }
    }
}

// Halcyon - the iPhone-style home screen that hosts Symbian apps.
// Licensed under the GNU General Public License v3 or later.

import SwiftUI
import UniformTypeIdentifiers

struct HomeScreenView: View {
    @EnvironmentObject private var controller: EmulatorController
    @State private var page: Int? = 0
    @State private var editing = false
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var shortcutTarget: SymbianApp?
    @State private var confirmUninstall: SymbianApp?

    var body: some View {
        ZStack {
            Wallpaper()

            VStack(spacing: 0) {
                topBar
                pages
                PageDots(count: controller.layout.pages.count, current: page ?? 0)
                    .padding(.vertical, 10)
                DockView(editing: $editing, menu: { app in AnyView(iconMenu(for: app)) })
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            if controller.isMock {
                MockBanner()
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: SymbianFileTypes.packages,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                controller.install(packages: urls)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(controller)
        }
        .sheet(item: $shortcutTarget) { app in
            HomeScreenShortcutSheet(app: app)
                .environmentObject(controller)
        }
        .confirmationDialog(confirmUninstall.map { "Remove \($0.name)?" } ?? "",
                            isPresented: Binding(get: { confirmUninstall != nil },
                                                 set: { if !$0 { confirmUninstall = nil } }),
                            titleVisibility: .visible,
                            presenting: confirmUninstall) { app in
            Button("Uninstall", role: .destructive) { controller.uninstall(app) }
            Button("Hide from Home Screen") {
                controller.layout.hide(app.uid)
                controller.saveLayout()
            }
        } message: { _ in
            Text("Uninstalling deletes the app and its data from the emulated phone.")
        }
        .onChange(of: controller.layout) { _, _ in controller.saveLayout() }
        .onChange(of: controller.importRequests) { _, _ in showingImporter = true }
    }

    private var topBar: some View {
        HStack {
            CircleButton(systemImage: "plus", tint: Color(red: 0.25, green: 0.33, blue: 0.75)) {
                showingImporter = true
            }
            .accessibilityLabel("Install Symbian app")
            Spacer()
            if editing {
                Button("Done") { withAnimation { editing = false } }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            } else {
                Menu {
                    Button { showingImporter = true } label: { Label("Install App…", systemImage: "plus.app") }
                    Button { withAnimation { editing = true } } label: { Label("Edit Home Screen", systemImage: "square.grid.3x3") }
                    if controller.runningApp != nil {
                        Button(role: .destructive) { controller.closeRunningApp() } label: {
                            Label("Close \(controller.runningApp?.name ?? "App")", systemImage: "xmark.circle")
                        }
                    }
                    Divider()
                    Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                } label: {
                    CircleButtonLabel(systemImage: "ellipsis", tint: Color(red: 0.2, green: 0.55, blue: 0.7))
                }
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Horizontally paged grid; works the same on iPhone, iPad and Mac.
    private var pages: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Array(controller.layout.pages.enumerated()), id: \.offset) { index, uids in
                    AppGrid(uids: uids, editing: $editing, menu: { app in AnyView(iconMenu(for: app)) })
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
    }

    @ViewBuilder
    private func iconMenu(for app: SymbianApp) -> some View {
        Button { controller.launch(uid: app.uid) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
        Button { shortcutTarget = app } label: {
            #if os(iOS)
            Label("Add to iPhone Home Screen…", systemImage: "plus.square.on.square")
            #else
            Label("Add to Applications & Dock…", systemImage: "dock.rectangle")
            #endif
        }
        if controller.layout.dock.contains(app.uid) {
            Button { controller.layout.moveToPage(app.uid, page: page ?? 0) } label: { Label("Remove from Dock", systemImage: "dock.arrow.down.rectangle") }
        } else if controller.layout.dock.count < HomeLayout.dockCapacity {
            Button { controller.layout.moveToDock(app.uid) } label: { Label("Add to Dock", systemImage: "dock.arrow.up.rectangle") }
        }
        Button { withAnimation { editing = true } } label: { Label("Edit Home Screen", systemImage: "square.grid.3x3") }
        Divider()
        Button(role: .destructive) { confirmUninstall = app } label: { Label("Remove App…", systemImage: "minus.circle") }
    }
}

// MARK: - Grid

struct AppGrid: View {
    @EnvironmentObject private var controller: EmulatorController
    let uids: [UInt32]
    @Binding var editing: Bool
    let menu: (SymbianApp) -> AnyView

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 22) {
            ForEach(uids, id: \.self) { uid in
                if let app = controller.app(uid: uid) {
                    AppIconView(app: app, editing: editing, showsLabel: true)
                        .onTapGesture {
                            if editing { return }
                            controller.launch(uid: uid)
                        }
                        .contextMenu { if !editing { menu(app) } }
                        .draggable(String(uid)) { AppIconView(app: app, editing: false, showsLabel: false) }
                        .dropDestination(for: String.self) { items, _ in
                            guard let moved = items.first.flatMap({ UInt32($0) }) else { return false }
                            withAnimation { controller.layout.move(moved, before: uid) }
                            return true
                        }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Dock

struct DockView: View {
    @EnvironmentObject private var controller: EmulatorController
    @Binding var editing: Bool
    let menu: (SymbianApp) -> AnyView

    var body: some View {
        HStack(spacing: 0) {
            ForEach(controller.layout.dock, id: \.self) { uid in
                if let app = controller.app(uid: uid) {
                    AppIconView(app: app, editing: editing, showsLabel: false)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { if !editing { controller.launch(uid: uid) } }
                        .contextMenu { if !editing { menu(app) } }
                        .draggable(String(uid)) { AppIconView(app: app, editing: false, showsLabel: false) }
                }
            }
            if controller.layout.dock.isEmpty {
                Text("Drag apps here")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 96)
        .background(.ultraThinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(.white.opacity(0.18)))
        .dropDestination(for: String.self) { items, _ in
            guard let moved = items.first.flatMap({ UInt32($0) }) else { return false }
            withAnimation { controller.layout.moveToDock(moved) }
            return true
        }
    }
}

// MARK: - Pieces

struct AppIconView: View {
    @EnvironmentObject private var controller: EmulatorController
    let app: SymbianApp
    let editing: Bool
    let showsLabel: Bool
    @State private var wiggle = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                if let image = controller.icon(for: app.uid) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    Text(String(app.name.prefix(1)))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.gray)
                }
                if controller.runningApp?.uid == app.uid {
                    Circle().fill(.white).frame(width: 6, height: 6)
                        .offset(y: 40)
                }
            }
            .frame(width: 66, height: 66)
            .rotationEffect(.degrees(editing ? (wiggle ? 2 : -2) : 0))
            .animation(editing ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .default, value: wiggle)
            .onAppear { wiggle = true }

            if showsLabel {
                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 80)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(.isButton)
    }
}

struct Wallpaper: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.20, green: 0.17, blue: 0.48),
                                Color(red: 0.16, green: 0.36, blue: 0.62),
                                Color(red: 0.27, green: 0.66, blue: 0.62)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            if count > 1 {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(index == current ? 0.95 : 0.4))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .frame(height: 8)
    }
}

struct CircleButton: View {
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleButtonLabel(systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

struct CircleButtonLabel: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Circle().fill(tint.opacity(0.85)))
            .overlay(Circle().strokeBorder(.white.opacity(0.25)))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

struct MockBanner: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Demo build: the emulator core is not included, so apps don't run.")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 116)
        }
        .allowsHitTesting(false)
    }
}

/// File types declared in Info.plist (UTImportedTypeDeclarations), so the file
/// picker filters correctly and "Open in Halcyon" works from Files, Safari and Mail.
enum SymbianFileTypes {
    static let sis = UTType(importedAs: "io.github.halcyon.sis-package", conformingTo: .data)
    static let sisx = UTType(importedAs: "io.github.halcyon.sisx-package", conformingTo: .data)
    static let packages: [UTType] = [sis, sisx]
    /// ROM dumps have no reliable extension (SYM.ROM, *.rom, *.bin, *.fpsx), so allow any file.
    static let firmware: [UTType] = [.data]
}

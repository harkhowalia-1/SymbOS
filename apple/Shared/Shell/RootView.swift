// SymbOS - top-level layout.
//
// The emulator surface is always in the view tree (the core needs it to boot and to
// keep rendering); the home screen sits on top of it and slides away when an app is
// opened. In Full Symbian mode the home screen is skipped and the emulated phone
// owns the whole window, like Parallels' full-screen mode.
//
// Licensed under the GNU General Public License v3 or later.

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var controller: EmulatorController
    @AppStorage("fullSymbianMode") private var fullSymbianMode = false

    private var showsHome: Bool {
        !fullSymbianMode && !controller.isShowingApp
    }

    var body: some View {
        ZStack {
            AppHostView(fullSymbianMode: fullSymbianMode)

            if showsHome {
                HomeScreenView()
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 1.08).combined(with: .opacity)))
            }

            switch controller.phase {
            case .needsFirmware:
                FirmwareSetupView()
                    .transition(.opacity)
            case .failed(let message):
                ContentUnavailableView("The emulator stopped", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                    .background(Wallpaper())
            case .waitingForSurface, .booting:
                if !showsHome || controller.apps.isEmpty {
                    BootingView()
                }
            case .ready:
                EmptyView()
            }

            if let message = controller.busyMessage {
                BusyOverlay(message: message)
            }
        }
        .animation(.spring(duration: 0.35), value: controller.isShowingApp)
        .animation(.easeInOut(duration: 0.25), value: fullSymbianMode)
        .sheet(item: $controller.textRequest) { request in
            TextEntrySheet(request: request)
                .environmentObject(controller)
        }
        .alert(controller.questionRequest?.message ?? "",
               isPresented: Binding(get: { controller.questionRequest != nil },
                                    set: { if !$0, controller.questionRequest != nil { controller.answerQuestion(first: false) } }),
               presenting: controller.questionRequest) { question in
            Button(question.firstButton.isEmpty ? "Yes" : question.firstButton) { controller.answerQuestion(first: true) }
            Button(question.secondButton.isEmpty ? "No" : question.secondButton, role: .cancel) { controller.answerQuestion(first: false) }
        }
        .sheet(item: $controller.installResult) { result in
            InstallResultSheet(result: result)
                .environmentObject(controller)
        }
    }
}

// MARK: - App host

/// The emulated screen plus a Belle-style softkey bar.
struct AppHostView: View {
    @EnvironmentObject private var controller: EmulatorController
    let fullSymbianMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            EmulatorSurface(view: controller.surfaceView)
                .background(Color.black)
            SoftkeyBar(fullSymbianMode: fullSymbianMode)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

struct SoftkeyBar: View {
    @EnvironmentObject private var controller: EmulatorController
    let fullSymbianMode: Bool

    var body: some View {
        HStack(spacing: 0) {
            softkey("Options", systemImage: "list.bullet") { controller.press(.leftSoftkey) }
            softkey("Menu", systemImage: "circle.grid.3x3.fill") { controller.press(.menu) }
            if !fullSymbianMode {
                softkey("Home", systemImage: "house") { controller.goHome() }
            }
            softkey("Back", systemImage: "arrow.uturn.backward") { controller.press(.rightSoftkey) }
        }
        .frame(height: 50)
        .background(
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .topTrailing) {
            if let fps = controller.fps, UserDefaults.standard.bool(forKey: "showFPS") {
                Text("\(Int(fps)) fps\(controller.usingJIT ? " · JIT" : "")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(4)
            }
        }
    }

    private func softkey(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Status overlays

struct BootingView: View {
    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Starting the phone…")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }
}

struct BusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(message).font(.callout).multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(40)
        }
    }
}

// MARK: - Dialogs from Symbian apps

struct TextEntrySheet: View {
    @EnvironmentObject private var controller: EmulatorController
    @State var request: EmulatorController.TextRequest
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Text", text: $request.text, axis: .vertical)
                    .focused($focused)
                    .lineLimit(1...6)
                    .onChange(of: request.text) { _, newValue in
                        if request.maxLength > 0, newValue.count > request.maxLength {
                            request.text = String(newValue.prefix(request.maxLength))
                        }
                    }
                if request.maxLength > 0 {
                    Text("\(request.text.count) of \(request.maxLength) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Enter text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { controller.answerText(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { controller.answerText(request.text) }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
        .interactiveDismissDisabled()
    }
}

struct InstallResultSheet: View {
    @EnvironmentObject private var controller: EmulatorController
    @Environment(\.dismiss) private var dismiss
    let result: EmulatorController.InstallResult
    @State private var shortcutTarget: SymbianApp?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(result.succeeded ? .green : .red)
                Text(result.fileName).font(.headline)
                Text(result.message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                ForEach(result.newApps) { app in
                    HStack(spacing: 12) {
                        AppIconView(app: app, editing: false, showsLabel: false)
                            .scaleEffect(0.7)
                            .frame(width: 50, height: 50)
                        Text(app.name).font(.body.weight(.medium))
                        Spacer()
                        Button("Open") {
                            dismiss()
                            controller.launch(uid: app.uid)
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            shortcutTarget = app
                        } label: {
                            Image(systemName: "plus.square.on.square")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Add to Home Screen")
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                }
                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $shortcutTarget) { app in
            HomeScreenShortcutSheet(app: app)
                .environmentObject(controller)
        }
    }
}

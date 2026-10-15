# Architecture

```
SwiftUI shell (apple/Shared/Shell)        home screen, installer, settings, app host + softkeys
        │ commands, events
EmulatorController (apple/Shared/Model)   boot, app list, launching, installs, dialogs, JIT choice
        │
HCEmulator / HCEmulatorView (Obj-C++)     apple/Shared/Bridge, mock core when not linked
        │ C++ calls
eka2l1::ios::bridge  (external/eka2l1/src/emu/ios)   iOS port's API; same code built for macOS by core/embed
        │
EKA2L1 core (kernel, reimplemented servers, Dynarmic JIT / dyncom interpreter, OpenGL)
```

Extensions (widgets, App Intents) never talk to the emulator. They read `apps.json`, `layout.json` and `icons/*.png`, which the app writes to the App Group container (`SharedStore`), and they open apps with the deep link `symbos://launch?uid=<hex UID>`.

## One surface, one phone

The core renders into a single surface: a `CAEAGLLayer` on iOS and an `NSView` with an `NSOpenGLContext` on macOS. `RootView` keeps that surface in the view tree at all times and draws the home screen above it, so the phone can boot while the home screen is showing. Opening an app moves the home screen away; Home pauses the guest, and reopening the same app resumes it.

The core runs one Symbian app at a time. Opening a different app calls `exit_game`, which reboots the guest in the background, then launches the new one.

## JIT

`JITSupport.applyToCoreConfig` writes `ios-enable-jit` into the core's `config.yml` before every boot:

- macOS: always true (Hardened Runtime with `com.apple.security.cs.allow-jit`).
- iOS: true only when the `CS_DEBUGGED` code-signing flag is set, i.e. StikDebug attached at launch. Otherwise the dyncom interpreter is used, so a normal launch never crashes.

## Patches to the core

`core/scripts/patch-core.py` makes three idempotent edits at build time; the submodule itself stays unmodified:

1. `src/emu/CMakeLists.txt`: on macOS, build `core/embed` instead of the Qt frontend.
2. `src/external/ffmpeg/CMakeLists.txt`: link the FFmpeg that `build-ffmpeg.sh` cross-compiles for iOS devices and Apple-silicon Macs.
3. `src/emu/ios/src/launcher.cpp`: route Symbian text-entry and yes/no dialogs to host hooks (`core/embed/halcyon_host.h`) instead of auto-answering them.

## Home screen icons outside the app

- **iOS, web clip:** `WebClipInstaller` builds a `.mobileconfig` with one `com.apple.webClip.managed` payload whose URL is the deep link, serves it once from `127.0.0.1`, and opens it in Safari. Sideloaded build only: App Store guideline 5.5 restricts apps that offer configuration profiles.
- **iOS, Shortcuts:** `OpenSymbianAppIntent` over `SymbianAppEntity`, also indexed in Spotlight.
- **macOS:** `LauncherAppGenerator` writes `~/Applications/SymbOS Apps/<App>.app` with a shell-script executable that opens the deep link, an `.icns` made from the Symbian icon, and an ad-hoc signature.

## Next steps

- Per-app windows on Mac and iPad (render each Symbian window group into its own window).
- Device bridges inside the reimplemented Symbian servers: PhotoKit behind a virtual `E:\Images`, the music library, Contacts and Calendar, camera, location.
- Snapshot widgets that show a Symbian app's last screen.
- Mac widgets (need a signed build with an App Group).
- Intel Mac support (an x86_64 FFmpeg and a universal core).

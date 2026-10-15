# SymbOS

Symbian^3 and Belle apps on iPhone, iPad and Mac, from a home screen that looks and works like the iPhone's.

Tap **+** to install a `.sis` or `.sisx` file and it lands on the home screen next to your phone's own apps. Put any Symbian app on the real iPhone Home Screen or in the Mac's Applications folder and Dock; tapping it opens straight into that app, the way Parallels runs Windows apps on a Mac. SymbOS is built on the open-source [EKA2L1](https://github.com/EKA2L1/EKA2L1) emulator and its [iOS port](https://github.com/mtwm1234/EKA2L1_IOS).

**Website and downloads:** https://harkhowalia-1.github.io/SymbOS (published by `.github/workflows/pages.yml`).

> Early development. The first build happens in GitHub Actions on the first push, and nothing has run on a device yet. Expect the first CI runs to need fixes.

## Features

- **Home screen:** pages, dock, drag to rearrange, long-press menus, hide or uninstall. Icons are decoded from your firmware and packages.
- **Installs:** the + button, "Open in SymbOS" from Files, Safari and Mail, or File › Install App on the Mac.
- **Real home screen icons:** a web-clip profile (sideloaded iPhone build) or the Shortcuts app on iOS; Parallels-style launcher apps in `~/Applications/SymbOS Apps` on the Mac.
- **Spotlight, Siri and Shortcuts:** every installed Symbian app is an App Intents entity ("Open Angry Birds in SymbOS").
- **Widgets:** phone clock, one-app launcher, dock apps, and a Control Center button (iOS 18+).
- **Native text entry:** Symbian text dialogs open the iPhone or Mac keyboard; yes/no prompts become real alerts.
- **JIT:** always on the Mac; on iPhone when launched from StikDebug, with an automatic fallback to the interpreter.
- **Full Symbian mode:** hide the home screen and give the emulated phone the whole window (experimental).

## Repository layout

| Path | What it is |
|---|---|
| `external/eka2l1` | The EKA2L1 iOS port, as an unmodified git submodule. |
| `core/scripts/` | Build the core as one static library per platform: `build-core.sh ios` / `build-core.sh macos`. `patch-core.py` applies three small, idempotent build patches at build time. |
| `core/embed/` | The macOS build of the core's bridge (reuses the iOS port's platform layer with the NSOpenGL context) and the native-dialog hooks header. |
| `apple/` | XcodeGen project: the iPhone/iPad app (`iOS/`), the Mac app (`macOS/`), shared SwiftUI shell, Objective-C++ bridge and App Intents (`Shared/`), and widgets (`Widgets/`). |
| `site/` | The download website and the AltStore / SideStore source generator. |
| `.github/workflows/` | `build.yml` builds the core and both apps and publishes `SymbOS.ipa` and `SymbOS.dmg`; `pages.yml` publishes the website. |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit together.

## Building

Requirements: a Mac with Xcode 16 or later, and `brew install xcodegen ninja`.

```sh
git clone --recursive https://github.com/harkhowalia-1/SymbOS
cd SymbOS
core/scripts/build-core.sh ios      # iPhone/iPad core (long first build)
core/scripts/build-core.sh macos    # Mac core
cd apple && xcodegen generate && open SymbOS.xcodeproj
```

Skip the two `build-core.sh` lines to work on the interface: the apps then build against a mock core with sample apps and a "Demo build" banner.

### Releases

Push to `main` with a new number in `VERSION`. The Build apps workflow builds everything and publishes the release `v<VERSION>` with `SymbOS.ipa` and `SymbOS.dmg`; the Website workflow then refreshes `apps.json` so SideStore and AltStore users get the update.

For a Mac build that opens without the right-click step, add these repository secrets: `MAC_CERT_P12` (base64 Developer ID Application certificate), `MAC_CERT_PASSWORD`, `MAC_SIGN_IDENTITY`, and for notarization `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD`.

### Renaming

The app name, bundle IDs, App Group, URL scheme and website URL are set in `apple/Config/Base.xcconfig`. The AltStore source's bundle ID is in `site/build_source.py`.

## Firmware and apps

SymbOS does not include, download or link to firmware, ROMs or commercial Symbian apps. Users dump firmware from a phone they own (ROM + RPKG via [Dumber](https://github.com/eka2l1/dumber)). The website's guide explains how.

## License

GPL-3.0-or-later, the same as EKA2L1. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

SymbOS is not affiliated with or endorsed by Nokia, HMD Global, Accenture or Apple. Symbian and Nokia are trademarks of their respective owners.

## Support

If you enjoy this project, you can support me here:

<a href="https://buymeacoffee.com/harkhowalia"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-orange.png" alt="Buy me a coffee" height="50"></a>

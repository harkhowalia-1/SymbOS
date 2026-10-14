#!/usr/bin/env python3
"""Build an AltStore / SideStore source (apps.json) from GitHub releases.

    python3 site/build_source.py releases.json owner/repo https://owner.github.io/repo > apps.json

`releases.json` is the output of `gh api repos/<owner>/<repo>/releases`. Every
release with a Halcyon.ipa asset becomes a version; the newest is listed first.
Standard library only.
"""
import json
import sys

APP_NAME = "Halcyon"
BUNDLE_ID = "io.github.harkhowalia1.halcyon"
TINT = "3d5aa8"

DESCRIPTION = (
    "Run Symbian^3 and Belle apps and games on iPhone and iPad, from a home screen "
    "that looks and works like the iPhone's. Install .sis and .sisx files with the + "
    "button, add Symbian apps to your real Home Screen, and launch from StikDebug for JIT speed.\n\n"
    "You need firmware dumped from a Symbian phone you own. Built on the open-source "
    "EKA2L1 emulator. Not affiliated with Nokia or HMD Global."
)


def main():
    releases_path, repo, pages = sys.argv[1], sys.argv[2], sys.argv[3].rstrip("/")
    try:
        with open(releases_path) as f:
            releases = json.load(f)
    except (OSError, ValueError):
        releases = []

    versions = []
    for release in releases:
        if release.get("draft"):
            continue
        ipa = next((a for a in release.get("assets", []) if a.get("name", "").endswith(".ipa")), None)
        if not ipa:
            continue
        versions.append({
            "version": release.get("tag_name", "0").lstrip("v"),
            "date": release.get("published_at") or release.get("created_at"),
            "localizedDescription": (release.get("body") or "")[:2000],
            "downloadURL": ipa["browser_download_url"],
            "size": ipa.get("size", 0),
            "minOSVersion": "18.0",
        })

    app = {
        "name": APP_NAME,
        "bundleIdentifier": BUNDLE_ID,
        "developerName": repo.split("/")[0],
        "subtitle": "Symbian apps with an iPhone-style home screen.",
        "localizedDescription": DESCRIPTION,
        "iconURL": f"{pages}/assets/icon-ios-512.png",
        "tintColor": TINT,
        "category": "utilities",
        "screenshots": [],
        "versions": versions,
        "appPermissions": {
            "entitlements": ["com.apple.security.application-groups", "get-task-allow"],
            "privacy": {
                "NSMotionUsageDescription": "Symbian games that use the tilt sensor read your device's motion.",
                "NSLocalNetworkUsageDescription": "Adding an app to your Home Screen briefly serves a profile to Safari from this device.",
            },
        },
    }
    if versions:
        latest = versions[0]
        # Older AltStore clients read these top-level fields.
        app.update({
            "version": latest["version"],
            "versionDate": latest["date"],
            "downloadURL": latest["downloadURL"],
            "size": latest["size"],
        })

    source = {
        "name": APP_NAME,
        "identifier": f"{BUNDLE_ID}.source",
        "subtitle": "Symbian emulator for iPhone and iPad",
        "description": DESCRIPTION,
        "iconURL": f"{pages}/assets/icon-ios-512.png",
        "website": pages,
        "tintColor": TINT,
        "apps": [app],
        "news": [],
    }
    json.dump(source, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()

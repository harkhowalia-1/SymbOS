#!/usr/bin/env python3
"""Draw Halcyon's app icon (an original design) and write every size the
asset catalogs and the website need.

    python3 apple/icon/make_icons.py

Requires Pillow. Re-run after changing the design; outputs are committed.
"""
import json
import pathlib

from PIL import Image, ImageDraw, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent
APPLE = HERE.parent
ROOT = APPLE.parent
S = 1024  # master size


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, stops):
    """Diagonal gradient through `stops` (list of RGB), top-left to bottom-right."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            seg = min(int(t * (len(stops) - 1)), len(stops) - 2)
            local = t * (len(stops) - 1) - seg
            px[x, y] = lerp(stops[seg], stops[seg + 1], local)
    return img


def master(rounded_mask=False):
    scale = 4  # supersample for smooth edges
    big = S * scale
    bg = gradient(S, [(51, 43, 122), (41, 92, 158), (69, 168, 158)]).resize((big, big), Image.BICUBIC)
    draw = ImageDraw.Draw(bg, "RGBA")

    # Phone body.
    pw, ph = big * 0.46, big * 0.72
    px0, py0 = (big - pw) / 2, (big - ph) / 2 + big * 0.01
    r = big * 0.075
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([px0, py0 + big * 0.025, px0 + pw, py0 + ph + big * 0.025], r, fill=(10, 20, 50, 110))
    bg.paste(shadow, (0, 0), shadow.filter(ImageFilter.GaussianBlur(big * 0.02)))
    draw.rounded_rectangle([px0, py0, px0 + pw, py0 + ph], r, fill=(250, 251, 253, 255))

    # Screen.
    m = big * 0.035
    sx0, sy0, sx1, sy1 = px0 + m, py0 + m * 1.6, px0 + pw - m, py0 + ph - m * 3.2
    draw.rounded_rectangle([sx0, sy0, sx1, sy1], big * 0.035, fill=(38, 70, 140, 255))

    # 3x4 grid of app tiles on the screen.
    cols, rows = 3, 4
    gap = (sx1 - sx0) * 0.09
    tw = ((sx1 - sx0) - gap * (cols + 1)) / cols
    th = tw
    total_h = rows * th + (rows - 1) * gap
    top = sy0 + ((sy1 - sy0) - total_h) / 2
    colors = [(255, 255, 255, 235), (255, 255, 255, 200), (125, 220, 205, 255), (255, 255, 255, 200)]
    for row in range(rows):
        for col in range(cols):
            x = sx0 + gap + col * (tw + gap)
            y = top + row * (th + gap)
            fill = colors[(row + col) % len(colors)]
            draw.rounded_rectangle([x, y, x + tw, y + th], tw * 0.24, fill=fill)

    # Menu key below the screen.
    kw = pw * 0.22
    ky = (sy1 + py0 + ph) / 2
    draw.rounded_rectangle([big / 2 - kw / 2, ky - big * 0.011, big / 2 + kw / 2, ky + big * 0.011], big * 0.011, fill=(150, 160, 180, 255))

    img = bg.resize((S, S), Image.LANCZOS)
    if rounded_mask:
        mask = Image.new("L", (S * 4, S * 4), 0)
        inset = S * 4 * 0.1
        ImageDraw.Draw(mask).rounded_rectangle([inset, inset, S * 4 - inset, S * 4 - inset], S * 4 * 0.18, fill=255)
        mask = mask.resize((S, S), Image.LANCZOS)
        out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        out.paste(img, (0, 0), mask)
        return out
    return img.convert("RGB")


def write_catalog(path, contents):
    path.mkdir(parents=True, exist_ok=True)
    (path / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main():
    ios = master(rounded_mask=False)
    mac = master(rounded_mask=True)

    # iOS: single 1024 icon (Xcode 14+ generates the rest).
    ios_set = APPLE / "Resources/iOS.xcassets/AppIcon.appiconset"
    write_catalog(APPLE / "Resources/iOS.xcassets", {"info": {"author": "xcode", "version": 1}})
    ios_set.mkdir(parents=True, exist_ok=True)
    ios.save(ios_set / "icon-1024.png")
    write_catalog(ios_set, {
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    })
    launch = APPLE / "Resources/iOS.xcassets/LaunchBackground.colorset"
    write_catalog(launch, {
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": "0.200", "green": "0.170", "blue": "0.480", "alpha": "1.000"}}}],
        "info": {"author": "xcode", "version": 1},
    })

    # macOS: the classic size set.
    mac_set = APPLE / "Resources/macOS.xcassets/AppIcon.appiconset"
    write_catalog(APPLE / "Resources/macOS.xcassets", {"info": {"author": "xcode", "version": 1}})
    mac_set.mkdir(parents=True, exist_ok=True)
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon-{pt}@{scale}x.png"
            mac.resize((px, px), Image.LANCZOS).save(mac_set / name)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    write_catalog(mac_set, {"images": images, "info": {"author": "xcode", "version": 1}})

    # Website and DMG.
    site = ROOT / "site/assets"
    site.mkdir(parents=True, exist_ok=True)
    mac.resize((512, 512), Image.LANCZOS).save(site / "icon-512.png")
    mac.resize((180, 180), Image.LANCZOS).save(site / "apple-touch-icon.png")
    mac.resize((64, 64), Image.LANCZOS).save(site / "favicon.png")
    ios.resize((512, 512), Image.LANCZOS).save(site / "icon-ios-512.png")
    print("Icons written.")


if __name__ == "__main__":
    main()

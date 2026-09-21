#!/usr/bin/env python3
"""BiLoom placeholder icon generator.

Draws the BiLoom orange-gold placeholder mark and writes it over every raster
icon the app ships (Android adaptive-legacy mipmaps, Play Store listing icon,
desktop PNG/ICO, tray icons).

Why a script instead of the upstream SVG pipeline: upstream regenerates icons
from `assets_source/images/icon/*.svg` via `dart run tool/generate_status_icons.dart`,
which needs `rsvg-convert` (librsvg) on PATH. This script needs only Pillow and
keeps the placeholder reproducible until the real artwork lands.

Usage:
    python tool/biloom_placeholder_icons.py [--root .]

The mark: three rounded gold bars on a deep charcoal field, echoing the
upstream geometry so the fork still reads as a network client.
"""

import argparse
import os
import struct
import zlib

from PIL import Image, ImageDraw

# --- brand palette -----------------------------------------------------------
BG = (20, 17, 12, 255)          # #14110C deep charcoal
GOLD_LIGHT = (245, 196, 107, 255)   # #F5C46B
GOLD = (232, 163, 61, 255)          # #E8A33D  primary
GOLD_DARK = (200, 134, 42, 255)     # #C8862A

SUPERSAMPLE = 4


def _rounded_bar(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def render_mark(size, rounded_corner=False):
    """Return an RGBA image of the BiLoom mark at the requested pixel size."""
    s = size * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # field
    if rounded_corner:
        d.ellipse((0, 0, s - 1, s - 1), fill=BG)
    else:
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.22), fill=BG)

    # three bars, rotated as a group to keep the loom diagonal
    bars = [
        # (vertical offset from centre, length, thickness, colour)
        (-0.185, 0.560, 0.135, GOLD_LIGHT),
        (0.000, 0.470, 0.135, GOLD),
        (0.185, 0.170, 0.135, GOLD_DARK),
    ]
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    cx, cy = s / 2, s / 2
    thickness = int(s * bars[0][2])
    for dy, length, thick, colour in bars:
        w = int(s * length)
        h = int(s * thick)
        left = cx - w / 2
        top = cy + s * dy - h / 2
        _rounded_bar(ld, (left, top, left + w, top + h), radius=h // 2, fill=colour)
    layer = layer.rotate(-20, resample=Image.BICUBIC, center=(cx, cy))

    # clip the rotated bars to the field so nothing spills outside the shape
    mask = Image.new("L", (s, s), 0)
    md = ImageDraw.Draw(mask)
    if rounded_corner:
        md.ellipse((0, 0, s - 1, s - 1), fill=255)
    else:
        md.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.22), fill=255)
    img.alpha_composite(Image.composite(layer, Image.new("RGBA", (s, s), (0, 0, 0, 0)), mask))

    return img.resize((size, size), Image.LANCZOS)


def png_bytes(img):
    """Minimal PNG encoder used only for sanity checks in tests."""
    raw = b"".join(b"\x00" + img.convert("RGBA").tobytes()[y * img.width * 4:(y + 1) * img.width * 4]
                   for y in range(img.height))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", img.width, img.height, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def render_tray(state, size):
    """Tray mark for a connection state: 1 idle, 2 connecting, 3 connected.

    Drawn rather than rasterised from SVG so the fork does not need
    rsvg-convert on the build machine.
    """
    palettes = {
        1: (138, 122, 94, 255),    # muted warm grey - idle
        2: (232, 163, 61, 255),    # amber - connecting
        3: (245, 196, 107, 255),   # bright gold - connected
    }
    colour = palettes.get(state, palettes[1])
    s = size * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    cx, cy = s / 2, s / 2
    thickness = int(s * 0.185)
    for dy, length in ((-0.20, 0.72), (0.0, 0.58), (0.20, 0.22)):
        w = int(s * length)
        h = thickness
        left = cx - w / 2
        top = cy + s * dy - h / 2
        _rounded_bar(ld, (left, top, left + w, top + h), radius=h // 2, fill=colour)
    layer = layer.rotate(-20, resample=Image.BICUBIC, center=(cx, cy))
    img.alpha_composite(layer)
    return img.resize((size, size), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="project root (default: cwd)")
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    written = []

    # --- Android legacy mipmaps (square + round), size preserved from disk ---
    res = os.path.join(root, "android", "app", "src", "main", "res")
    if os.path.isdir(res):
        for entry in sorted(os.listdir(res)):
            if not entry.startswith("mipmap-") or "anydpi" in entry:
                continue
            d = os.path.join(res, entry)
            if not os.path.isdir(d):
                continue
            for name, is_round in (("ic_launcher.webp", False), ("ic_launcher_round.webp", True)):
                target = os.path.join(d, name)
                if not os.path.exists(target):
                    continue
                with Image.open(target) as cur:
                    w, h = cur.size
                img = render_mark(w, rounded_corner=is_round)
                img.save(target, format="WEBP", lossless=True, quality=100)
                written.append((os.path.relpath(target, root), f"{w}x{h}"))

        store = os.path.join(root, "android", "app", "src", "main", "ic_launcher-playstore.png")
        if os.path.exists(store):
            with Image.open(store) as cur:
                w, h = cur.size
            render_mark(w).save(store, format="PNG")
            written.append((os.path.relpath(store, root), f"{w}x{h}"))

    # --- desktop app icon ----------------------------------------------------
    assets = os.path.join(root, "assets", "images")
    if os.path.isdir(assets):
        png = os.path.join(assets, "icon.png")
        if os.path.exists(png):
            with Image.open(png) as cur:
                w, h = cur.size
            render_mark(w).save(png, format="PNG")
            written.append((os.path.relpath(png, root), f"{w}x{h}"))

        ico = os.path.join(assets, "icon.ico")
        if os.path.exists(ico):
            with Image.open(ico) as cur:
                sizes = sorted({s[0] for s in cur.info.get("sizes", {})}) or [16, 32, 48, 256]
            base = render_mark(max(sizes))
            base.save(ico, format="ICO", sizes=[(n, n) for n in sizes])
            written.append((os.path.relpath(ico, root), ",".join(str(n) for n in sizes)))

    # --- tray status icons ---------------------------------------------------
    tray = os.path.join(assets, "tray") if os.path.isdir(assets) else None
    if tray and os.path.isdir(tray):
        for root_dir, _dirs, files in os.walk(tray):
            for name in sorted(files):
                if not (name.endswith(".png") or name.endswith(".ico")):
                    continue
                state = 1 if "status_1" in name else 2 if "status_2" in name else 3
                target = os.path.join(root_dir, name)
                with Image.open(target) as cur:
                    if name.endswith(".ico"):
                        sizes = sorted({s[0] for s in cur.info.get("sizes", set())}) or [16, 32, 48]
                        render_tray(state, max(sizes)).save(
                            target, format="ICO", sizes=[(n, n) for n in sizes]
                        )
                        written.append((os.path.relpath(target, root), ",".join(str(n) for n in sizes)))
                    else:
                        w, h = cur.size
                        render_tray(state, w).save(target, format="PNG")
                        written.append((os.path.relpath(target, root), f"{w}x{h}"))

    if not written:
        print("nothing written - check --root")
        return
    for path, size in written:
        print(f"rewrote {path}  ({size})")


if __name__ == "__main__":
    main()

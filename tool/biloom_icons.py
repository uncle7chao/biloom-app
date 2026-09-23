#!/usr/bin/env python3
"""BiLoom icon generator - rasterises the brand mark over every icon the app ships.

Replaces tool/biloom_placeholder_icons.py.

Why not upstream's pipeline: `dart run tool/generate_status_icons.dart` needs
`rsvg-convert` (librsvg) on PATH. The fork *does* ship the tray sources
(`assets_source/images/icon/status_{1,2,3}.svg`, tracked in git), but no rasteriser is
installed on the build machine - verified absent: rsvg-convert, inkscape, magick.
(Those three SVGs are left exactly as upstream: this script does not read them, and
re-colouring them could not reproduce our tray glyphs anyway.)
(Watch out: `C:\\Windows\\system32\\convert.EXE` is the NTFS conversion tool, not
ImageMagick.) This script needs only Pillow, so the icons stay reproducible anywhere.

Adaptive icons
--------------
The raster mipmaps are only consulted below API 26. From API 26 up the launcher reads
`mipmap-anydpi-v26/ic_launcher.xml`, which resolves to `@color/ic_launcher_background`
plus `@drawable/ic_launcher_foreground`. So this script also *writes* those three files
from the brand SVG - rewriting the webp files alone changes nothing on any modern
device. They were still the orange-gold placeholder until 2026-09-22.

Palette
-------
One brand pair, used everywhere: BRAND #00E5AF on INK #101010. It covers launcher,
store, tray, desktop, TV banner, the window/exe icons and the logo drawn inside the
app UI (title bar, About page) - there is no second palette to keep in sync.

(The warm pair #E8A33D on #14110C was tried for the in-app logo and retired on
2026-09-22: it split the product into "orange inside, green outside" - Linux and
Windows show the in-app asset as the installed application icon, so the same app
appeared orange in the dock and green on the phone.)

No outline/stroke variants: the brand sources are solid-fill only.

Optical sizing
--------------
The mark is a solid green square with the B carved OUT of it, so its legibility is
decided by the negative space. The B's strokes are 42 of the mark's 838 units - 5%.
Shrunk into a 16 px icon that lands at 0.6 px and the B dissolves into a blob.

Every output therefore picks the trace whose weight matches how large the mark
actually *appears* (not how large the file is):

    mark height >= 22 px   -> biloom-mark.svg           (original trace, gap 42/838)
    15 .. 21.99 px         -> biloom-mark-simple.svg    (K=16 erosion, gap 74/838)
    < 15 px                -> biloom-mark-micro.svg     (K=24 erosion, gap 90/838)

`biloom-mark-medium.svg` (K=8, gap 58/838) is outside the bands on purpose: it is only
used where an asset is pinned to it by hand, currently just the 34 px title-bar logo.

Those thresholds are measured, not guessed. The eroded traces are a *heavy* geometry
change: K=16 thickens the B's strokes from 42 to 74 of the mark's 838 units (+76%),
which is exactly what rescues a tiny icon but reads as a distorted letterform the
moment the mark is big enough to resolve it. Rendered legibility:

    16 px icon (mark 12 px)   unreadable even with the original trace
    24 px icon (mark 18 px)   only the silhouette reads
    32 px icon (mark 24 px)   clear with the original trace

so the original trace owns everything from a 22 px mark upwards.

Banding uses the *display* size. `assets/images/icon.png` is pinned to the original
trace explicitly rather than banded: it is a hero element (64 px on the About page) and
it doubles as the Linux package icon (`linux/packaging/{appimage,deb,rpm}/make_config.yaml`
-> `icon: ./assets/images/icon.png`) and as upstream's source for the Windows exe icon
(`tool/generate_status_icons.dart`), so the deformation must not reach it at any size.
The 34 px title-bar logo therefore gets its own asset instead - see `plan()`.

Geometry
--------
Field style follows the platform convention, verified against upstream FlClash
(a10cfb6): the Play icon is opaque and full-bleed, launcher icons are a rounded
shape with transparent corners. The mark occupies 74% of the canvas height (13%
padding), matching design/logo/biloom-appicon-mark.svg.

Usage:
    python tool/biloom_icons.py --root . [--dry-run]
"""

import argparse
import math
import os
import re
import struct
import sys

from PIL import Image, ImageDraw, ImageFilter

BRAND = (0, 229, 175, 255)        # #00E5AF - the only brand colour, everywhere
INK = (16, 16, 16, 255)           # #101010
MUTED = (122, 138, 136, 255)      # #7A8A88 - tray state 1 (stopped)
SS = 4                            # supersample factor
MARK_FRAC = 0.74                  # mark height as a fraction of the canvas
RADIUS = 0.22                     # rounded-field corner radius, fraction of size
APPLE_RADIUS = 0.2237             # macOS squircle
ADAPTIVE_DP = 108                 # android adaptive-icon canvas
ADAPTIVE_VIEWPORT = 240           # vector units; keeps the path numbers readable
ADAPTIVE_CONTENT_DP = 64          # mark size inside the adaptive canvas. The safe zone
                                  # is a 72 dp square, but a circular mask only spans
                                  # 66 dp, and this mark is a square - so 64 dp keeps
                                  # its corners inside the circle.

TRACE_ORIGINAL = "biloom-mark.svg"
TRACE_MEDIUM = "biloom-mark-medium.svg"
TRACE_SIMPLE = "biloom-mark-simple.svg"
TRACE_MICRO = "biloom-mark-micro.svg"

_TILE = re.compile(r"([MmLlCcZzHhVv])|([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)")


# --------------------------------------------------------------------------- svg
def _parse_path(d):
    """Flatten an absolute M/L/C/Z path into a list of point lists (viewBox units).

    Only the commands this project's generator emits are supported. Cubic segments
    are sampled adaptively so that a 4096 px supersample canvas still has no
    visible facets.
    """
    toks = [m.group(1) or float(m.group(2)) for m in _TILE.finditer(d)]
    subpaths, cur, pen, start = [], [], (0.0, 0.0), (0.0, 0.0)
    i = 0
    cmd = None
    while i < len(toks):
        t = toks[i]
        if isinstance(t, str):
            cmd = t
            i += 1
            if cmd in "Zz":
                if cur:
                    subpaths.append(cur)
                    cur = []
                pen = start
                continue
            continue
        if cmd is None:
            i += 1
            continue
        c = cmd.upper()
        if c == "M":
            x, y = toks[i], toks[i + 1]
            i += 2
            cur = [(x, y)]
            pen = start = (x, y)
        elif c == "L":
            x, y = toks[i], toks[i + 1]
            i += 2
            cur.append((x, y))
            pen = (x, y)
        elif c == "C":
            c1 = (toks[i], toks[i + 1])
            c2 = (toks[i + 2], toks[i + 3])
            p3 = (toks[i + 4], toks[i + 5])
            i += 6
            approx = (abs(c1[0] - pen[0]) + abs(c1[1] - pen[1])
                      + abs(c2[0] - c1[0]) + abs(c2[1] - c1[1])
                      + abs(p3[0] - c2[0]) + abs(p3[1] - c2[1]))
            n = max(6, min(240, int(approx / 2.2)))
            for s in range(1, n + 1):
                t0 = s / n
                mt = 1 - t0
                cur.append((
                    mt ** 3 * pen[0] + 3 * mt * mt * t0 * c1[0]
                    + 3 * mt * t0 * t0 * c2[0] + t0 ** 3 * p3[0],
                    mt ** 3 * pen[1] + 3 * mt * mt * t0 * c1[1]
                    + 3 * mt * t0 * t0 * c2[1] + t0 ** 3 * p3[1],
                ))
            pen = p3
        else:
            i += 1
    if cur:
        subpaths.append(cur)
    return subpaths


def _point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    for k in range(n):
        x1, y1 = poly[k]
        x2, y2 = poly[(k + 1) % n]
        if (y1 > y) != (y2 > y):
            if x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                inside = not inside
    return inside


def _nesting_depth(rings, i):
    """Even-odd nesting depth of ring i: how many sibling rings enclose it.

    Needed because fill-rule="evenodd" applies across the whole path: a letter
    counter is depth 1 and must be punched out of its letter, while the mark's three
    rings are disjoint siblings at depth 0 and simply union.
    """
    x, y = rings[i][0]
    return sum(1 for j, r in enumerate(rings) if j != i and _point_in_poly(x, y, r))


class Shape:
    """A brand SVG flattened once, reusable at any size."""

    def __init__(self, path):
        raw = open(path, encoding="utf-8").read()
        vb = re.search(r'viewBox="([-\d.\s]+)"', raw)
        self.x0, self.y0, self.w, self.h = [float(v) for v in vb.group(1).split()]
        self.subpaths = []
        for m in re.finditer(r"<path([^>]*?)/>", raw, re.S):
            attrs = m.group(1)
            d = re.search(r'd="([^"]+)"', attrs)
            if not d:
                continue
            dx = dy = 0.0
            tr = re.search(r'translate\(([-\d.]+)[ ,]([-\d.]+)\)', attrs)
            if tr:
                dx, dy = float(tr.group(1)), float(tr.group(2))
            rings = [[(x + dx, y + dy) for x, y in sp]
                     for sp in _parse_path(d.group(1)) if len(sp) >= 3]
            if not rings:
                continue
            depths = [_nesting_depth(rings, i) for i in range(len(rings))]
            self.subpaths.append(list(zip(rings, depths)))

    def mask(self, out_w, out_h, ss=SS):
        """Rasterise the ink into an 'L' mask of out_w*ss by out_h*ss pixels."""
        W, H = int(round(out_w * ss)), int(round(out_h * ss))
        scale = min(W / self.w, H / self.h)
        ox = (W - self.w * scale) / 2 - self.x0 * scale
        oy = (H - self.h * scale) / 2 - self.y0 * scale
        m = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(m)
        for group in self.subpaths:
            # paint shallow rings first so deeper ones punch holes in them
            for sp, depth in sorted(group, key=lambda t: t[1]):
                pts = [(x * scale + ox, y * scale + oy) for x, y in sp]
                if len(pts) >= 3:
                    d.polygon(pts, fill=255 if depth % 2 == 0 else 0)
        return m


def _field(size, style, ink=INK, ss=SS):
    """Opaque field + optional alpha mask for the icon background."""
    S = size * ss
    field = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(field)
    if style == "round":
        fd.ellipse((0, 0, S - 1, S - 1), fill=ink)
    elif style == "flat":
        fd.rectangle((0, 0, S - 1, S - 1), fill=ink)
    else:
        r = int((APPLE_RADIUS if style == "squircle" else RADIUS) * S)
        fd.rounded_rectangle((0, 0, S - 1, S - 1), radius=r, fill=ink)
    return field


def _tint(mask, colour):
    img = Image.new("RGBA", mask.size, colour)
    img.putalpha(mask)
    return img


def pick_trace(mark_px):
    """Choose the trace whose weight matches the mark's displayed pixel height.

    See the module docstring for the measured thresholds. The bands are deliberately
    conservative about when the eroded (distorted) traces are allowed in: they are only
    ever correct where the letterform cannot be resolved anyway.
    """
    if mark_px >= 22:
        return TRACE_ORIGINAL
    if mark_px >= 15:
        return TRACE_SIMPLE
    return TRACE_MICRO


class IconBuilder:
    def __init__(self, brand_dir):
        self.dir = brand_dir
        self._shapes = {}
        self._masks = {}

    def shape(self, name):
        if name not in self._shapes:
            self._shapes[name] = Shape(os.path.join(self.dir, name))
        return self._shapes[name]

    def mark_mask(self, trace, out_w, out_h):
        key = (trace, round(out_w, 2), round(out_h, 2))
        if key not in self._masks:
            self._masks[key] = self.shape(trace).mask(out_w, out_h)
        return self._masks[key]

    def app_icon(self, size, style="rounded", mark_frac=MARK_FRAC, display=None,
                 opaque=False, brand=BRAND, ink=INK, trace=None):
        """Compose the mark on its dark field. Returns an RGBA image of `size`.

        `trace` overrides the banded pick - pass it when a specific asset must always
        carry the true letterform regardless of its rendered size.
        """
        display = display if display is not None else size
        trace = trace or pick_trace(display * mark_frac)
        field = _field(size, "flat" if opaque else style, ink=ink)
        mh = size * mark_frac
        shape = self.shape(trace)
        mw = mh * shape.w / shape.h
        mask = self.mark_mask(trace, mw, mh)
        field.alpha_composite(_tint(mask, brand),
                              (int((field.width - mask.width) / 2),
                               int((field.height - mask.height) / 2)))
        return field.resize((size, size), Image.LANCZOS)

    def mark_only(self, size, mark_frac=0.86, display=None, colour=BRAND, ring=False,
                  trace=None):
        """Transparent-background mark, for tray icons and the title-bar logo."""
        display = display if display is not None else size
        trace = trace or pick_trace(display * mark_frac)
        shape = self.shape(trace)
        S = size * SS
        mh = size * mark_frac
        mw = mh * shape.w / shape.h
        m = self.mark_mask(trace, mw, mh)
        if ring:
            # TUN state reads as a hollow mark: keep only the outer band.
            # MinFilter(k) erodes (k-1)/2 supersampled pixels per side.
            k = max(3, int(round(size * 0.10 * SS)) * 2 + 1)
            eroded = m.filter(ImageFilter.MinFilter(k))
            m = Image.composite(Image.new("L", m.size, 0), m, eroded)
        out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        out.alpha_composite(_tint(m, colour),
                            (int((S - m.width) / 2), int((S - m.height) / 2)))
        return out.resize((size, size), Image.LANCZOS)

    def banner(self, size=(320, 180)):
        """Android TV banner: mark on the left, wordmark on the right."""
        W, H = size
        img = Image.new("RGBA", (W * SS, H * SS), INK)
        # The banner mark is over 100 px tall, so it bands like everything else; a
        # hardcoded eroded trace here put a visibly distorted B on the TV banner.
        trace = pick_trace(H * 0.62)
        shape = self.shape(trace)
        mh = H * 0.62
        mw = mh * shape.w / shape.h
        m = self.mark_mask(trace, mw, mh)
        x = int(W * 0.075) * SS
        img.alpha_composite(_tint(m, BRAND), (x, int((img.height - m.height) / 2)))
        word = self.shape("biloom-wordmark.svg")
        wh = H * 0.20
        ww = wh * word.w / word.h
        wm = word.mask(ww, wh)
        img.alpha_composite(_tint(wm, BRAND),
                            (x + m.width + int(W * 0.05) * SS,
                             int((img.height - wm.height) / 2)))
        return img.resize((W, H), Image.LANCZOS)


# ------------------------------------------------------------------- drawables
_VECTOR = """<?xml version="1.0" encoding="utf-8"?>
<!-- GENERATED by tool/biloom_icons.py from assets_source/brand/{src} - do not hand-edit.
     From API 26 up the launcher renders THIS, not mipmap-*/ic_launcher.webp. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
        android:width="{dp}dp"
        android:height="{dp}dp"
        android:viewportWidth="{vp}"
        android:viewportHeight="{vp}">
    <group android:scaleX="{s:.6f}"
           android:scaleY="{s:.6f}"
           android:translateX="{dx:.4f}"
           android:translateY="{dy:.4f}">
        <path
                android:fillColor="{colour}"
                android:fillType="evenOdd"
                android:pathData="{d}" />
    </group>
</vector>
"""

_BACKGROUND = """<?xml version="1.0" encoding="utf-8"?>
<!-- GENERATED by tool/biloom_icons.py. -->
<resources>
    <color name="ic_launcher_background">{colour}</color>
</resources>
"""


def _hex(rgb):
    return "#%02X%02X%02X" % rgb[:3]


def adaptive_files(root, brand_dir):
    """(path, text) for the adaptive-icon resources Android 8+ actually renders.

    The raster mipmaps are only consulted below API 26. From API 26 up the launcher
    reads mipmap-anydpi-v26/ic_launcher.xml, which resolves to
    @color/ic_launcher_background + @drawable/ic_launcher_foreground. Regenerating the
    webp files therefore changes nothing on any modern device unless these are written
    too - they were still the orange-gold placeholder.
    """
    mark = os.path.join(brand_dir, TRACE_ORIGINAL)
    shape = Shape(mark)
    raw = open(mark, encoding="utf-8").read()
    # Require whitespace before the attribute: a bare r'd="' also matches the tail of
    # id="..." and would silently return the wrong value.
    d = " ".join(re.findall(r'\s+d="([^"]+)"', raw, re.S)[0].split())

    scale = (ADAPTIVE_CONTENT_DP / ADAPTIVE_DP * ADAPTIVE_VIEWPORT) / shape.h
    dx = (ADAPTIVE_VIEWPORT - shape.w * scale) / 2 - shape.x0 * scale
    dy = (ADAPTIVE_VIEWPORT - shape.h * scale) / 2 - shape.y0 * scale
    drawable = _VECTOR.format(src=os.path.basename(mark), dp=ADAPTIVE_DP,
                              vp=ADAPTIVE_VIEWPORT, s=scale, dx=dx, dy=dy,
                              colour=_hex(BRAND), d=d)

    res = os.path.join(root, "android", "app", "src", "main", "res")
    if not os.path.isdir(res):
        return []
    return [
        (os.path.join(res, "values", "ic_launcher_background.xml"),
         _BACKGROUND.format(colour=_hex(INK))),
        (os.path.join(res, "drawable", "ic_launcher_foreground.xml"), drawable),
        (os.path.join(res, "drawable", "ic_launcher_foreground_tv.xml"), drawable),
    ]


# --------------------------------------------------------------------------- ico
def build_ico(entries):
    """entries: list of (size, png_bytes). PNG-compressed entries (Vista+)."""
    n = len(entries)
    header = struct.pack("<HHH", 0, 1, n)
    offset = 6 + 16 * n
    directory, blob = b"", b""
    for size, png in entries:
        dim = 0 if size >= 256 else size
        directory += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(png), offset)
        offset += len(png)
        blob += png
    return header + directory + blob


def _png_bytes(img):
    import io
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


# --------------------------------------------------------------------------- plan
def _tray(builder, size, state):
    """Tray glyph. state: 1 = stopped, 2 = running / system proxy, 3 = running / TUN."""
    colour = MUTED if state == 1 else BRAND
    return builder.mark_only(size, mark_frac=0.92, ring=(state == 3), colour=colour)


def plan(root):
    """Entries: (path, fn(builder, size|None) -> RGBA, save kwargs, label).

    `fn` is called once per size for multi-size .ico targets and once with None for
    everything else, so one call site drives both shapes of output.
    """
    items = []
    res = os.path.join(root, "android", "app", "src", "main", "res")
    if os.path.isdir(res):
        for entry in sorted(os.listdir(res)):
            if not entry.startswith("mipmap-") or "anydpi" in entry:
                continue
            d = os.path.join(res, entry)
            if not os.path.isdir(d):
                continue
            for name, style in (("ic_launcher.webp", "rounded"),
                                ("ic_launcher_round.webp", "round")):
                target = os.path.join(d, name)
                if not os.path.exists(target):
                    continue
                with Image.open(target) as cur:
                    w = cur.size[0]
                # NOT opaque: launcher icons keep their shape with transparent corners
                # (ic_launcher_round must stay circular). Only the Play listing icon is
                # full-bleed opaque. Verified against upstream FlClash at a10cfb6.
                items.append((target,
                              (lambda w, st: lambda b, s=None: b.app_icon(w, st))(w, style),
                              dict(format="WEBP", lossless=True, quality=100),
                              f"{w}x{w} {style}"))

        play = os.path.join(root, "android", "app", "src", "main",
                            "ic_launcher-playstore.png")
        if os.path.exists(play):
            items.append((play, lambda b, s=None: b.app_icon(512, "flat", opaque=True),
                          dict(format="PNG"), "512x512 flat/opaque"))

        banner = os.path.join(res, "mipmap-xhdpi", "ic_banner.png")
        if os.path.exists(banner):
            with Image.open(banner) as cur:
                sz = cur.size
            items.append((banner, (lambda sz: lambda b, s=None: b.banner(sz))(sz),
                          dict(format="PNG"), f"{sz[0]}x{sz[1]} banner"))

    # The logo drawn INSIDE the app UI uses the same green palette as everything else.
    # This asset is not only in-app art: it is also the Linux package icon
    # (linux/packaging/{appimage,deb,rpm}/make_config.yaml) and upstream's source for
    # the Windows exe icon (tool/generate_status_icons.dart), so whatever colour lands
    # here is what the operating system shows for the installed application.
    #
    # It is 550 px on disk but rendered at 34 px (title bar) and 64 px (About page);
    # 64 px is large enough that a user reads the actual letterform, so this asset is
    # pinned to the original trace rather than banded. (It used to band on display=64,
    # which the old 48 px threshold pushed into the K=16 eroded trace - the B's strokes
    # are 76% heavier there, and that distortion is plain to see at 550 px / 64 px.)
    png = os.path.join(root, "assets", "images", "icon.png")
    if os.path.exists(png):
        with Image.open(png) as cur:
            w = cur.size[0]
        items.append((png,
                      (lambda w: lambda b, s=None: b.app_icon(
                          w, "rounded", display=64, trace=TRACE_ORIGINAL))(w),
                      dict(format="PNG"), f"{w}x{w} in-app (original trace)"))

    ico = os.path.join(root, "assets", "images", "icon.ico")
    if os.path.exists(ico):
        items.append((ico,
                      lambda b, s=None: b.app_icon(s, "rounded"),
                      dict(format="ICO"), "in-app / window icon"))

    # The sidebar logo. AppIcon in lib/manager/window_manager.dart draws a 50 px chip
    # (AppShape.md) in surfaceContainerHighest and places this asset inside its 8 px
    # padding at 34 px. That chip is NOT a dark plate: the sidebar behind it is
    # surfaceContainer, and the two only differ by 1.11:1 - effectively invisible.
    #
    # So this asset has to carry its own dark backing. The mark is a green square with
    # the B punched OUT of it, which means the letterform IS the contrast between the
    # green and whatever shows through the hole. Measured against the light chip that
    # contrast is 1.28:1 and the B disappears outright; against #101010 it is 11.6:1.
    #
    # Hence: a plated tile, not a bare mark. A bare mark used to be here and it read as
    # a plain green blob in the light theme.
    #
    # It also takes the K=8 trace rather than the original: at 34 px the original's
    # stroke is 34 * 0.90 * (42/838) = 1.53 px, the K=8 trace 2.12 px. K=8 is +38% on
    # the letterform - a third of what K=16 does - so it stays recognisable as the mark
    # while surviving at sidebar size. Mark at 90% leaves a 1.7 px rim, which is the
    # widest mark that still gives an even, non-aliased edge at this size.
    # 192 px on disk is ~1.9x the 3x-density need.
    titlebar = os.path.join(root, "assets", "images", "icon_titlebar.png")
    items.append((titlebar,
                  lambda b, s=None: b.app_icon(192, "rounded", mark_frac=0.90,
                                               trace=TRACE_MEDIUM),
                  dict(format="PNG"), "sidebar tile 34px (plated, K=8)"))

    win = os.path.join(root, "windows", "runner", "resources", "app_icon.ico")
    if os.path.exists(win):
        items.append((win, lambda b, s=None: b.app_icon(s, "rounded"),
                      dict(format="ICO"), "multi-size"))

    macos = os.path.join(root, "macos", "Runner", "Assets.xcassets",
                         "AppIcon.appiconset")
    if os.path.isdir(macos):
        for name in sorted(os.listdir(macos)):
            if not name.startswith("app_icon_") or not name.endswith(".png"):
                continue
            size = int(name[len("app_icon_"):-4])
            items.append((os.path.join(macos, name),
                          (lambda n: lambda b, s=None: b.app_icon(n, "squircle"))(size),
                          dict(format="PNG"), f"{size}x{size} squircle"))

    tray = os.path.join(root, "assets", "images", "tray")
    if os.path.isdir(tray):
        for base, _dirs, files in os.walk(tray):
            for name in sorted(files):
                if not (name.endswith(".png") or name.endswith(".ico")):
                    continue
                state = 1 if "status_1" in name else 2 if "status_2" in name else 3
                target = os.path.join(base, name)
                if name.endswith(".ico"):
                    items.append((target,
                                  (lambda st: lambda b, s=None: _tray(b, s, st))(state),
                                  dict(format="ICO"), f"state{state} multi-size"))
                else:
                    with Image.open(target) as cur:
                        w = cur.size[0]
                    items.append((target,
                                  (lambda w, st: lambda b, s=None: _tray(b, w, st))(
                                      w, state),
                                  dict(format="PNG"), f"{w}x{w} state{state}"))

    return items


ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
TRAY_ICO_SIZES = [16, 20, 24, 32, 40, 48, 64]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    brand = os.path.join(root, "assets_source", "brand")
    if not os.path.isdir(brand):
        sys.exit(f"missing brand sources: {brand}")
    b = IconBuilder(brand)

    written = 0
    for path, fn, save_kw, label in plan(root):
        rel = os.path.relpath(path, root)
        is_ico = path.lower().endswith(".ico")
        sizes = (TRAY_ICO_SIZES if "tray" in rel else ICO_SIZES) if is_ico else []
        if args.dry_run:
            tail = f"; {','.join(str(s) for s in sizes)}" if is_ico else ""
            print(f"[dry] {rel}  ({label}{tail})")
        elif is_ico:
            open(path, "wb").write(
                build_ico([(s, _png_bytes(fn(b, s))) for s in sizes]))
            print(f"wrote {rel}  ({','.join(str(s) for s in sizes)})")
        else:
            fn(b, None).save(path, **save_kw)
            print(f"wrote {rel}  ({label})")
        written += 1

    for path, text in adaptive_files(root, brand):
        rel = os.path.relpath(path, root)
        if args.dry_run:
            print(f"[dry] {rel}  (adaptive icon, generated)")
        else:
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
            print(f"wrote {rel}  (adaptive icon, generated)")
        written += 1

    print(f"\n{written} assets {'planned' if args.dry_run else 'written'}")


if __name__ == "__main__":
    main()

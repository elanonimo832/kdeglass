#!/usr/bin/env python3
"""
measure-icon-geometry.py — measures the macOS icon squircle from a real screenshot.

WHY THIS EXISTS (M5)
    docs/ROADMAP.md: "The squircle radii of the folder icons are missing. There are iOS values in
    the kit, but the macOS ones could not be confirmed." The primary source is not the kit: it is
    the user's own macOS screenshots in `muestras/` (gitignored, and never committed). This tool
    measures the icon corner in those pixels instead of deducing it from an iOS figure.

    What it measures is the CORNER PROFILE: for every row of the corner, the subpixel x where the
    icon's body starts. From that profile it fits three families, each with its free parameter:

        circle        inset(dy) = R - sqrt(R^2 - (R - dy)^2)          one parameter: R
        Figma squircle  the kit's own construction (`cornerSmoothing`)  two: R, smoothing
        superellipse  |x/R|^n + |y/R|^n = 1, centred on the arc centre    two: R, n

    and it reports the best fit AND the residual of each. The residual is the point: at the ~96 px
    an icon is drawn at on a 4K screenshot, the difference between a circular corner and a
    continuous one is at the edge of one pixel, so a single number without its residual would be
    claiming a precision the pixels do not have.

THE FIGMA CONSTRUCTION IS IMPORTED, NOT COPIED
    `effect-kwin/measure-corner.py` already implements the kit's corner (`inset_figma`), and this
    repository refuses to keep two copies of one formula: the shader and `simulate.py` had to be
    fixed together for exactly that reason. So this tool imports that file.

USAGE
    python3 measure-icon-geometry.py --self-test
    python3 measure-icon-geometry.py --image muestras/Untitled3.png --grid 40,210
    python3 measure-icon-geometry.py --render evidence/2026-10-15-m5-icon-corner.png

    --self-test  draws a corner of a KNOWN radius, reads it back, and checks it recovers it. A
                 number from a photo is a measurement only if the reader has been shown to work.
    --image      a screenshot plus the band (`y0,y1`) that holds the icons; it finds the icons,
                 measures their top-left corner, and prints one line per icon.
    --render     draws the measured profile against the fitted families, for `evidence/`.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MEASURE_CORNER = os.path.join(ROOT, "effect-kwin", "measure-corner.py")

RADIOS = tuple(np.arange(12.0, 32.01, 0.25))
SMOOTHINGS = tuple(np.arange(0.0, 1.001, 0.05))
EXPONENTES = (2.0, 2.25, 2.5, 2.75, 3.0, 3.25, 3.5, 4.0, 4.5, 5.0, 6.0)


def radius_grid(lo=12.0, hi=32.0, step=0.25):
    """The radii a fit is allowed to choose from.

    THE DEFAULT IS THE APP ICON'S OWN RANGE, and that is on purpose: the published M5 figure was
    measured with it, so widening the default would move a number that is already written down in
    order to flatter a new one. A macOS FOLDER's body corner turns out to be about 5 px, well BELOW
    12, so the folder has to ask for its own range on the command line (`--radius-min/--radius-max`)
    -- and the first run without it reported `R = 12.00, error 6.92 px`, which is a grid edge and not
    a measurement.
    """
    return tuple(np.arange(float(lo), float(hi) + 1e-9, float(step)))


def load_measure_corner():
    """The kit's corner construction lives in ONE place; this tool imports it."""
    spec = importlib.util.spec_from_file_location("measure_corner", MEASURE_CORNER)
    if spec is None or spec.loader is None:  # pragma: no cover
        raise RuntimeError(f"cannot import {MEASURE_CORNER}")
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


# ------------------------------------------------------------------------------------------------
# The three families, each as inset(dy): how far inside the corner box the boundary is, dy rows
# below the top edge. `dy = 0` is the top edge itself.
# ------------------------------------------------------------------------------------------------
def inset_circle(dy, radius):
    dy = np.asarray(dy, dtype=float)
    return radius - np.sqrt(np.maximum(radius * radius - np.maximum(radius - dy, 0.0) ** 2, 0.0))


def inset_superellipse(dy, radius, exponent):
    dy = np.asarray(dy, dtype=float)
    t = np.maximum(radius - dy, 0.0) / radius
    return radius - radius * np.maximum(1.0 - t**exponent, 0.0) ** (1.0 / exponent)


def inset_figma(dy, radius, smoothing, mc):
    return np.array([mc.inset_figma(float(k), float(radius), float(smoothing)) for k in np.asarray(dy)])


# ------------------------------------------------------------------------------------------------
# READING THE CORNER OUT OF PIXELS
# ------------------------------------------------------------------------------------------------
def corner_profile(lum, x_edge, y_edge, rows=22, background=None, body=None, corner="tl"):
    """Subpixel inset per row for ONE corner of the body.

    The edge is found as the 0.5 crossing of a linear ramp between the background and the icon's
    body, which is what antialiasing gives you: a hard threshold would quantise the measurement to
    whole pixels and a 96 px icon's radius would come out in 1 px steps. The background and the body
    are sampled LOCALLY (a few px either side of the edge), because a screenshot's wallpaper has a
    gradient across it and a global colour would drift.

    There is NO `polarity` here on purpose. The coverage interpolates from the background to the body
    whatever their order, so a LIGHT icon on a dark wallpaper (the Launchpad) and a DARK blue folder
    on a white one (the Finder) go through the same crossing. The polarity only decides which pixels
    a capture calls "body", and that is `find_icons`'s job, not this reader's.

    `corner` matters for a FOLDER: its TAB occupies the top-left of the icon, so the body's corner
    has to be read on the RIGHT, where nothing covers it.

    The search is WINDOWED, and that is not a detail. Reading the first light pixel of the WHOLE row
    finds whatever is brightest elsewhere in the screenshot: on the first real run that produced
    insets of 180, 360, 540 px -- the icon grid's own spacing -- with residuals that grew by one
    grid step per icon. The corner lives within a radius of the icon's edge, so the crossing is
    looked for there and nowhere else.
    """
    if corner not in ("tl", "tr", "bl", "br"):
        raise ValueError(f"unknown corner {corner!r}")
    # `out_x`/`out_y` point from the body's edge OUTWARD, towards the background.
    out_x = -1 if corner in ("tl", "bl") else +1
    out_y = -1 if corner in ("tl", "tr") else +1

    def box(yc, xc, hy=2, hx=3):
        ys = np.clip(np.arange(int(round(yc)) - hy, int(round(yc)) + hy + 1), 0, lum.shape[0] - 1)
        xs = np.clip(np.arange(int(round(xc)) - hx, int(round(xc)) + hx + 1), 0, lum.shape[1] - 1)
        return float(np.median(lum[np.ix_(ys, xs)]))

    if background is None:
        background = box(y_edge + out_y * 4, x_edge + out_x * 4)
    if body is None:
        body = box(y_edge - out_y * 16, x_edge - out_x * 6)
    profiles = []
    for k in range(rows):
        # `out_y` points towards the BACKGROUND, and the profile walks the other way: into the body.
        # (Getting this backwards reads the rows above a top edge, where the body does not exist yet,
        # and every profile comes back NaN -- which is how it was caught.)
        y = y_edge - out_y * k
        if y < 0 or y >= lum.shape[0]:
            break
        row = lum[y]
        # The window is NARROW on the edge's side and wide on the body's: the crossing is within a
        # few px of the edge, and a wide window on the background side is where the neighbouring
        # icon's body sits.
        if out_x < 0:
            xa, xb = max(x_edge - 6, 0), min(x_edge + 80, row.shape[0])
        else:
            xa, xb = max(x_edge - 80, 0), min(x_edge + 6, row.shape[0])
        window_ = row[xa:xb]
        cov = (window_ - background) / (body - background) if body != background else window_ * 0.0
        idx = np.where(cov > 0.5)[0]
        if len(idx) == 0:
            profiles.append(np.nan)
            continue
        if out_x < 0:
            # the body is on the INWARD side of the edge: to the RIGHT of a left edge, so the first
            # covered pixel going right is the crossing.
            jw = int(idx.min())
            if jw <= 0:
                profiles.append(abs(float(xa + jw) - x_edge))
                continue
            lo, hi = cov[jw - 1], cov[jw]
            t = (0.5 - lo) / (hi - lo) if hi > lo else 0.0
            edge = (xa + jw - 1) + t
        else:
            # ... and to the LEFT of a right edge, so the crossing is the LAST covered pixel.
            jw = int(idx.max())
            if jw >= len(cov) - 1:
                profiles.append(abs(float(xa + jw) - x_edge))
                continue
            hi, lo = cov[jw], cov[jw + 1]
            t = (hi - 0.5) / (hi - lo) if hi > lo else 0.0
            edge = (xa + jw) + t
        profiles.append(abs(edge - x_edge))
    return np.array(profiles, dtype=float)


def fit_all(profile, mc, radios=None):
    """Best fit of each family, with its residual. The residual is what says how much to believe.

    `radios` defaults to the app icons' own range; a caller measuring a smaller corner (a folder's
    body) passes its own, and the fit says which range it used by returning it.
    """
    radios = RADIOS if radios is None else tuple(radios)
    dy = np.arange(len(profile), dtype=float)
    ok = ~np.isnan(profile)
    # FIVE rows, not eight. The guard exists so a profile that is mostly NaN is not "fitted", and for
    # the app icons (22 rows) any threshold in this range does the same job. But a macOS FOLDER's body
    # corner is over in SIX rows -- its body tapers below that -- so a guard of eight refused to
    # measure the very case M5 asked about: the command printed "no icons measured" with the corner
    # sitting right there in the profile.
    if ok.sum() < 5:
        return None
    medido = profile[ok]
    d = dy[ok]

    def error(model):
        return float(np.max(np.abs(model - medido)))

    best_c = min((error(inset_circle(d, R)), R) for R in radios)
    best_f = min((error(inset_figma(d, R, s, mc)), R, s)
                  for R in radios for s in SMOOTHINGS)
    best_s = min((error(inset_superellipse(d, R, n)), R, n)
                  for R in radios for n in EXPONENTES)
    return {
        "circle": {"radius": best_c[1], "error": best_c[0]},
        "figma": {"radius": best_f[1], "smoothing": best_f[2], "error": best_f[0]},
        "superellipse": {"radius": best_s[1], "exponent": best_s[2], "error": best_s[0]},
        "radios": (radios[0], radios[-1]),
        "rows": int(ok.sum()),
    }


def find_icons(lum, y0, y1, threshold=180.0, minimum=40, polarity="light", x_range=None):
    """The x runs of the icons inside the band [y0, y1).

    `polarity` is which way the body differs from the background: the Launchpad draws LIGHT icons on
    a dark wallpaper and the Finder draws DARK blue folders on a white one. The default threshold
    (180 of 255) separates them in both captures, but a caller can move it.

    `x_range` (x0, x1) restricts the search to a column band, which a Finder capture needs: its
    SIDEBAR is a tall grey-blue panel that a dark polarity reads as one more icon.
    """
    banda = lum[y0:y1]
    mass = ((banda > threshold) if polarity == "light" else (banda < threshold)).sum(axis=0)
    if x_range is not None:
        x0, x1 = int(x_range[0]), int(x_range[1])
        keep = np.zeros_like(mass, dtype=bool)
        keep[max(x0, 0):x1] = True
        mass = np.where(keep, mass, 0)
    cut = max(4, int(0.25 * (y1 - y0)))
    runs, s = [], None
    for x, v in enumerate(mass > cut):
        if v and s is None:
            s = x
        if not v and s is not None:
            if x - s >= minimum:
                runs.append((s, x - 1))
            s = None
    if s is not None and len(mass) - s >= minimum:
        runs.append((s, len(mass) - 1))
    return runs


def measure_icon(lum, x_edge, y_edge, side, mc, rows=22, corner="tl", radios=None):
    profile = corner_profile(lum, x_edge, y_edge, rows=rows, corner=corner)
    ajuste = fit_all(profile, mc, radios=radios)
    if ajuste is None:
        return None
    ajuste["profile"] = profile
    ajuste["side"] = float(side)
    ajuste["x"] = int(x_edge)
    ajuste["y"] = int(y_edge)
    ajuste["corner"] = corner
    ajuste["rows"] = int(rows)
    return ajuste


def measure_band(path, y0, y1, mc=None, polarity="light", corner="tl", threshold=180.0,
                 radios=None, x_range=None, rows=22):
    """Measure every icon found in the band. Returns the list of measurements.

    `corner` picks which corner of each icon is read, and that decides BOTH the edge that is used as
    the corner's x and the probe window that finds the icon's top edge. For a folder it has to be a
    RIGHT corner: the tab sits on the top-left, so a probe on the left finds the TAB and would put
    the icon's top edge three rows above the body's -- and then the top-right profile would be read
    in rows where the body does not exist yet.
    """
    mc = mc or load_measure_corner()
    im = Image.open(path).convert("RGB")
    lum = np.asarray(im, dtype=float).mean(axis=2)
    results = []

    def is_body(v):
        return (v > threshold) if polarity == "light" else (v < threshold)

    for (xa, xb) in find_icons(lum, y0, y1, threshold=threshold, polarity=polarity,
                               x_range=x_range):
        # the icon's true edges and its side, measured on a row well inside the body
        row = lum[y0 + int(0.6 * (y1 - y0))]
        body = np.where(is_body(row))[0]
        body = body[(body >= xa - 4) & (body <= xb + 4)]
        if len(body) < 20:
            continue
        left, right = int(body.min()), int(body.max())
        # the probe window: on the side of the corner being measured, so a folder's TAB is not what
        # the top edge is found from.
        if corner in ("tl", "bl"):
            pa, pb = left, min(left + 60, lum.shape[1])
        else:
            pa, pb = max(right - 60, 0), right
        edge_row = None
        if corner in ("tl", "tr"):
            for y in range(max(y0 - 20, 0), min(y0 + 60, lum.shape[0])):
                if is_body(lum[y, pa:pb]).sum() >= 20:
                    edge_row = y
                    break
        else:
            for y in range(min(y1 + 20, lum.shape[0] - 1), max(y0 - 20, -1), -1):
                if is_body(lum[y, pa:pb]).sum() >= 20:
                    edge_row = y
                    break
        if edge_row is None:
            continue
        # THE SIDE IS MEASURED ON A ROW INSIDE THE BODY, and not as "the widest row". Under every
        # Launchpad icon there is a LIGHT LABEL with the app's name, so the widest light row in the
        # icon's column is the LABEL, not the icon: the first version took 112 px and 150 px for a
        # 96 px icon. A row 30 px into the body is inside the icon whatever the label does.
        # ... and the window is the icon's OWN run, not a fixed 160 px: a Finder grid puts the next
        # folder ~154 px away, so a fixed window read `side = 160` for a 118 px folder and then fed
        # that inflated side into `R/S`.
        probe = int(np.clip(edge_row + (30 if corner in ("tl", "tr") else -30),
                            max(y0 - 20, 0), lum.shape[0] - 1))
        c = np.where(is_body(lum[probe, max(xa - 4, 0):xb + 5]))[0]
        side = int(c.max() - c.min() + 1) if len(c) >= 20 else 0
        if side < 40:
            continue
        x_edge = left if corner in ("tl", "bl") else right
        m = measure_icon(lum, x_edge, edge_row, side, mc, rows=rows, corner=corner, radios=radios)
        if m is not None:
            results.append(m)
    return results


# ------------------------------------------------------------------------------------------------
# SELF-TEST: draw a corner of a KNOWN radius and read it back
# ------------------------------------------------------------------------------------------------
def draw_icon(radius, side=96, smoothing=0.0, mc=None, ss=8):
    """A synthetic icon whose top-left corner is EXACTLY `radius` (circle) or the kit's corner."""
    mc = mc or load_measure_corner()
    ancho = side + 30
    n = ancho * ss
    ys, xs = np.mgrid[0:n, 0:n]
    px = (xs + 0.5) / ss - 0.5
    py = (ys + 0.5) / ss - 0.5
    # the corner's boundary as a distance field: inside the rounded rectangle?
    x0, y0 = 15.0, 15.0          # the icon's top-left in the canvas
    if smoothing > 0.0:
        # THE KIT'S OWN CONSTRUCTION, IN ITS OWN FRAME. `figma_curve` already returns the top-left
        # corner from (0, p) on the left edge to (p, 0) on the top, with (0, 0) AT THE OUTER VERTEX
        # -- so the icon's left edge is x = 0 and its top edge is y = 0, and no offset is needed
        # beyond the icon's own position in the canvas. (Getting this wrong is how the first version
        # of this self-test produced no profile at all.)
        curve = np.array(mc.figma_curve(radius, smoothing, samples=400), dtype=float)
        # the curve is monotone from (0, p) to (p, 0), so it is a function y(x) and the icon's body
        # is BELOW it: interpolate the boundary and compare, which is a vector op and not a loop.
        p_corner = float(curve[-1, 0])
        ys_curva = np.interp(np.clip(px - x0, 0.0, p_corner), curve[:, 0], curve[:, 1])
        inside = (px >= x0) & (py >= y0)
        inside &= (px >= x0 + p_corner) | (py >= y0 + p_corner) | (py >= y0 + ys_curva)
    else:
        cx, cy = x0 + radius, y0 + radius
        d = np.sqrt((px - cx) ** 2 + (py - cy) ** 2)
        inside = ((px >= x0 + radius) & (py >= y0)) | ((px >= x0) & (py >= y0 + radius)) | (d <= radius)
    # the icon's other three corners are square here: the reader only looks at the top-left
    inside &= (px >= x0) & (py >= y0)
    # coverage by supersampling, like measure-corner's own renderer
    cov = inside.reshape(ancho, ss, ancho, ss).mean(axis=(1, 3))
    img = np.zeros((ancho, ancho), dtype=float)
    img[:] = 0.30                                     # the background
    img = img * (1.0 - cov) + 0.92 * cov              # the icon's body
    return img


def self_test():
    """The reader must recover a radius it was given. A measurement tool that cannot do this
    turns a coincidence into a number."""
    mc = load_measure_corner()
    fallos = []
    for radius in (14.0, 20.0, 26.0):
        img = draw_icon(radius, side=96, smoothing=0.0, mc=mc)
        profile = corner_profile(img, 15, 15, rows=22)
        ajuste = fit_all(profile, mc)
        if ajuste is None:
            fallos.append(f"R={radius}: the reader produced no profile")
            continue
        r = ajuste["circle"]["radius"]
        e = abs(r - radius)
        print(f"  self-test circle R={radius:<5} -> recovered {r:<6} error {e:.2f} px")
        if e > 1.0:
            fallos.append(f"R={radius}: recovered {r}, off by {e:.2f} px")
    # and the same reader on the kit's OWN corner, with a smoothing, must also recover the radius
    img = draw_icon(20.0, side=96, smoothing=0.6, mc=mc)
    profile = corner_profile(img, 15, 15, rows=22)
    ajuste = fit_all(profile, mc)
    if ajuste is None:
        fallos.append("squircle: no profile")
    else:
        print(f"  self-test kit corner s=0.6 -> circle fit R={ajuste['circle']['radius']} "
              f"(err {ajuste['circle']['error']:.2f}), figma fit R={ajuste['figma']['radius']} "
              f"s={ajuste['figma']['smoothing']} (err {ajuste['figma']['error']:.2f})")

    # A SECOND GEOMETRY AND A SECOND READ PATH. The app icons are ~20 px of radius on 96 and are read
    # on the TOP-LEFT; a macOS folder's body corner is ~5 px and has to be read on the TOP-RIGHT,
    # because its TAB occupies the top-left. Both are new code -- the small radius is BELOW the
    # default grid's 12 px floor -- and a path the self-test does not walk is a path nobody has shown
    # to work: the first version of the rewritten reader returned NaN on every row because it walked
    # the profile OUTWARDS, and only these cases caught it.
    for radius in (5.0, 8.0):
        img = draw_icon(radius, side=96, smoothing=0.0, mc=mc)
        ancho = img.shape[0]
        # `draw_icon` rounds the top-left corner; mirroring the canvas moves that corner to the
        # top-RIGHT, which is where a folder has to be read. The icon spans (15, 15) to (15+96, ...),
        # so after the mirror its right edge is at `ancho - 1 - 15`.
        mir = img[:, ::-1]
        profile = corner_profile(mir, ancho - 1 - 15, 15, rows=14, corner="tr")
        ajuste = fit_all(profile, mc, radios=radius_grid(2.0, 18.0))
        if ajuste is None:
            fallos.append(f"R={radius} top-right: the reader produced no profile")
            continue
        r = ajuste["circle"]["radius"]
        e = abs(r - radius)
        print(f"  self-test top-right R={radius:<5} -> recovered {r:<6} error {e:.2f} px")
        if e > 1.0:
            fallos.append(f"R={radius} top-right: recovered {r}, off by {e:.2f} px")

    # AND THE POLARITY: a light body on a dark background and its INVERSE must give the same runs.
    # That is the whole of what "polarity" means here, and the Finder's dark folders on a white
    # desktop are the case that needs it.
    bg, cuerpo = 0.20, 0.90
    claro = np.full((60, 200), bg)
    claro[:, 40:120] = cuerpo
    runs_l = find_icons(claro, 0, 60, threshold=0.5, polarity="light")
    runs_d = find_icons(1.0 - claro, 0, 60, threshold=0.5, polarity="dark")
    if runs_l != runs_d:
        fallos.append(f"find_icons polarity: light gives {runs_l}, dark gives {runs_d}")
    else:
        print(f"  self-test polarity      -> light and dark both find {runs_l}")

    if fallos:
        for f in fallos:
            print(f"  FAIL {f}", file=sys.stderr)
        return 1
    print("self-test: ok")
    return 0


# ------------------------------------------------------------------------------------------------
# RENDER: our own drawing of the measured geometry (never a crop of Apple's pixels)
# ------------------------------------------------------------------------------------------------
def render(out_path, path=None, y0=40, y1=210, **band_opts):
    """Our OWN drawing of the measured geometry -- never a crop of Apple's pixels. The repository
    does not redistribute them, and what has to be read here is the PROFILE, not the artwork.

    `band_opts` goes straight to `measure_band`, so the same drawing serves the app icons and the
    folder (a right-hand corner, a dark polarity, a few rows) instead of a second renderer that
    would drift from this one.
    """
    mc = band_opts.pop("mc", None) or load_measure_corner()
    if path is None:
        path = os.path.join(ROOT, "muestras", "Untitled3.png")
    measurements = measure_band(path, y0, y1, mc=mc, **band_opts)
    if not measurements:
        print("render: no icons measured", file=sys.stderr)
        return 1
    # THE WORST FITTING VALID ICON IS THE ONE DRAWN, and that is the point of the drawing: a plot
    # of the BEST fit would hide the residual the reader has to judge. Two earlier versions got
    # this wrong: one had a stray minus and drew the best fit while its caption claimed the worst,
    # and the next drew a REJECTED measurement, whose 8 px residual is a mis-detected corner and
    # not the difference between the models -- with a caption underneath saying they agreed.
    validas = [x for x in measurements if x["circle"]["error"] <= 2.0] or measurements
    m = max(validas, key=lambda d: d["circle"]["error"])
    scale, margin, top = 16, 60, 76
    rows = len(m["profile"])
    width, height = int(max(rows, 26) * scale) + 2 * margin, top + rows * scale + 110
    img = Image.new("RGB", (width, height), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.text((margin, 18), "M5 - the macOS icon corner, measured from the user's own screenshots",
           fill=(20, 20, 20))
    d.text((margin, 36), f"{len(measurements)} icons in this band, {len(measurements) - len(validas)} "
                         f"rejected on residual; the one drawn is the worst fit AMONG THE VALID ONES",
           fill=(90, 90, 90))
    ox, oy = margin, top
    dy = np.arange(rows)
    max_inset = float(np.nanmax(m["profile"]))
    d.line([(ox, oy), (ox + max_inset * scale + 24, oy)], fill=(215, 215, 215))
    d.line([(ox, oy), (ox, oy + rows * scale)], fill=(215, 215, 215))
    # the two families FIRST, the measured points ON TOP: the dots are the measurement, the lines
    # are the models, and the reader has to see which one the dots sit on.
    for valores, color, ancho in (
            (inset_circle(dy, m["circle"]["radius"]), (205, 60, 60), 3),
            (inset_figma(dy, m["figma"]["radius"], m["figma"]["smoothing"], mc), (30, 150, 60), 1)):
        pts = [(ox + float(v) * scale, oy + i * scale) for i, v in enumerate(valores)]
        d.line(pts, fill=color, width=ancho)
    for i, v in enumerate(m["profile"]):
        if np.isnan(v):
            continue
        d.ellipse([ox + v * scale - 3, oy + i * scale - 3, ox + v * scale + 3, oy + i * scale + 3],
                  fill=(20, 90, 200), outline=(255, 255, 255))
    ly = oy + rows * scale + 14
    d.text((ox, ly), f"measured profile ({rows - 1} rows, inset {max_inset:.1f} px at the top edge)",
           fill=(20, 90, 200))
    d.text((ox, ly + 18), f"circle      R = {m['circle']['radius']:.2f} px   residual {m['circle']['error']:.2f} px",
           fill=(205, 60, 60))
    d.text((ox, ly + 34), f"kit squircle s = {m['figma']['smoothing']:.2f}   residual {m['figma']['error']:.2f} px",
           fill=(30, 150, 60))
    d.text((ox, ly + 54), f"side {m['side']:.0f} px   ->   R/S = {m['circle']['radius'] / m['side']:.3f}",
           fill=(20, 20, 20))
    d.text((ox, ly + 72), "the two lines sit on each other: at this size the RADIUS is measurable and "
                         "the smoothing is not", fill=(90, 90, 90))
    img.save(out_path)
    print(f"wrote {out_path}")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description="Measure the macOS icon squircle in a screenshot.")
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--image")
    p.add_argument("--grid", help="the band that holds the icons, 'y0,y1'")
    p.add_argument("--corner", default="tl", choices=("tl", "tr", "bl", "br"),
                   help="which corner of each icon to read; a FOLDER needs a right one (its tab "
                        "covers the top-left)")
    p.add_argument("--polarity", default="light", choices=("light", "dark"),
                   help="whether the icons are LIGHTER (Launchpad) or DARKER (Finder folders) than "
                        "the background")
    p.add_argument("--threshold", type=float, default=180.0,
                   help="the value that separates body from background in the capture (0..255)")
    p.add_argument("--radius-min", type=float, default=12.0,
                   help="the smallest radius the fit may choose; the default is the app icons' own "
                        "floor, and a folder's body is well below it")
    p.add_argument("--radius-max", type=float, default=32.0)
    p.add_argument("--radius-step", type=float, default=0.25,
                   help="the fit's radius resolution; asking for finer than the default only makes "
                        "sense when the radius itself is small")
    p.add_argument("--rows", type=int, default=22,
                   help="how many rows of the corner profile to fit. A SMALL corner is over in a few "
                        "rows, and the rows past it carry the icon's own taper or its shadow: a "
                        "folder's body narrows by ~1.2 px below its corner, and fitting that in moved "
                        "R from 5.9 to 5.1 px. 6 rows is the corner itself, up to its first minimum")
    p.add_argument("--x-range", help="restrict the search to a column band, 'x0,x1'; a Finder "
                                     "capture needs it, because its sidebar reads as one more icon")
    p.add_argument("--render")
    p.add_argument("--tol", type=float, default=2.0,
                   help="a fit with a bigger residual than this is reported but NOT averaged in")
    a = p.parse_args(argv)
    if a.self_test:
        return self_test()
    if a.render:
        y0, y1 = (int(v) for v in (a.grid or "40,210").split(","))
        x_range = tuple(int(v) for v in a.x_range.split(",")) if a.x_range else None
        return render(a.render, path=a.image, y0=y0, y1=y1,
                      polarity=a.polarity, corner=a.corner, threshold=a.threshold,
                      radios=radius_grid(a.radius_min, a.radius_max, a.radius_step),
                      x_range=x_range, rows=a.rows)
    if a.image:
        y0, y1 = (int(v) for v in (a.grid or "40,210").split(","))
        mc = load_measure_corner()
        radios = radius_grid(a.radius_min, a.radius_max, a.radius_step)
        x_range = tuple(int(v) for v in a.x_range.split(",")) if a.x_range else None
        measurements = measure_band(a.image, y0, y1, mc=mc, polarity=a.polarity, corner=a.corner,
                                    threshold=a.threshold, radios=radios, x_range=x_range,
                                    rows=a.rows)
        if not measurements:
            print("no icons measured", file=sys.stderr)
            return 1
        print(f"{'x':>6} {'side':>5} {'R':>6} {'R/S':>6} {'err_circ':>9} {'err_figma':>9} {'s':>5}"
              f"   corner={a.corner} polarity={a.polarity} radii={a.radius_min:g}..{a.radius_max:g}")
        for m in measurements:
            mark = "" if m["circle"]["error"] <= a.tol else "   <- rejected"
            print(f"{m['x']:>6} {m['side']:>5.0f} {m['circle']['radius']:>6.2f} "
                  f"{m['circle']['radius'] / m['side']:>6.3f} {m['circle']['error']:>9.2f} "
                  f"{m['figma']['error']:>9.2f} {m['figma']['smoothing']:>5.2f}{mark}")
        # A MEASUREMENT WITH AN 8 px RESIDUAL IS NOT A MEASUREMENT. The statistic is taken over the
        # ones whose fit actually holds, and the rejected ones are printed and counted instead of
        # being averaged into the answer: an icon whose corner was mis-detected must not move the
        # number, and it must not disappear either.
        valid = [m for m in measurements if m["circle"]["error"] <= a.tol]
        rejected = len(measurements) - len(valid)
        if not valid:
            print(f"\nno icon fitted within {a.tol} px: the band or the threshold is wrong",
                  file=sys.stderr)
            return 1
        rs = [m["circle"]["radius"] / m["side"] for m in valid]
        print(f"\nR/S  mediana={np.median(rs):.4f}  media={np.mean(rs):.4f}  desv={np.std(rs):.4f}"
              f"  n={len(rs)} valid  ({rejected} rejected on residual > {a.tol} px)")
        return 0
    p.error("one of --self-test, --image or --render is required")


if __name__ == "__main__":
    sys.exit(main())

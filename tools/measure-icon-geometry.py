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
def corner_profile(lum, x_edge, y_edge, rows=22, background=None, body=None):
    """Subpixel inset per row for the TOP-LEFT corner.

    The edge is found as the 0.5 crossing of a linear ramp between the background and the icon's
    body, which is what antialiasing gives you: a hard threshold would quantise the measurement to
    whole pixels and a 96 px icon's radius would come out in 1 px steps. The background and the body
    are sampled LOCALLY (a few px either side of the edge), because a screenshot's wallpaper has a
    gradient across it and a global colour would drift.
    """
    if background is None:
        background = float(np.median(lum[y_edge - 6:y_edge - 2, max(x_edge - 6, 0):x_edge - 2]))
    if body is None:
        body = float(np.median(lum[y_edge + 12:y_edge + 20, x_edge + 3:x_edge + 9]))
    profiles = []
    for k in range(rows):
        y = y_edge + k
        if y >= lum.shape[0]:
            break
        row = lum[y]
        # THE SEARCH IS WINDOWED, and that is not a detail. Reading the first light pixel of the
        # WHOLE row finds whatever is brightest elsewhere in the screenshot: on the first real run
        # that produced insets of 180, 360, 540 px -- the icon grid's own spacing -- with residuals
        # that grew by one grid step per icon. The corner lives within a radius of the icon's left
        # edge, so the crossing is looked for there and nowhere else.
        xa = max(x_edge - 6, 0)
        xb = min(x_edge + 80, row.shape[0])
        window_ = row[xa:xb]
        cov = (window_ - background) / (body - background) if body != background else window_ * 0.0
        idx = np.where(cov > 0.5)[0]
        if len(idx) == 0:
            profiles.append(np.nan)
            continue
        jw = int(idx.min())          # the crossing, in the WINDOW's own coordinates
        j = jw + xa                  # ... and in the row's
        if j <= 0:
            profiles.append(float(j - x_edge))
            continue
        lo, hi = cov[jw - 1], cov[jw]
        t = (0.5 - lo) / (hi - lo) if hi > lo else 0.0
        profiles.append((j - 1) + t - x_edge)
    return np.array(profiles, dtype=float)


def fit_all(profile, mc):
    """Best fit of each family, with its residual. The residual is what says how much to believe."""
    dy = np.arange(len(profile), dtype=float)
    ok = ~np.isnan(profile)
    if ok.sum() < 8:
        return None
    medido = profile[ok]
    d = dy[ok]

    def error(model):
        return float(np.max(np.abs(model - medido)))

    best_c = min((error(inset_circle(d, R)), R) for R in RADIOS)
    best_f = min((error(inset_figma(d, R, s, mc)), R, s)
                  for R in RADIOS for s in SMOOTHINGS)
    best_s = min((error(inset_superellipse(d, R, n)), R, n)
                  for R in RADIOS for n in EXPONENTES)
    return {
        "circle": {"radius": best_c[1], "error": best_c[0]},
        "figma": {"radius": best_f[1], "smoothing": best_f[2], "error": best_f[0]},
        "superellipse": {"radius": best_s[1], "exponent": best_s[2], "error": best_s[0]},
        "rows": int(ok.sum()),
    }


def find_icons(lum, y0, y1, threshold=180.0, minimum=40):
    """The x runs of the icons inside the band [y0, y1): light bodies on a darker wallpaper."""
    banda = lum[y0:y1]
    mass = (banda > threshold).sum(axis=0)
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


def measure_icon(lum, x_edge, y_edge, side, mc, rows=22):
    profile = corner_profile(lum, x_edge, y_edge, rows=rows)
    ajuste = fit_all(profile, mc)
    if ajuste is None:
        return None
    ajuste["profile"] = profile
    ajuste["side"] = float(side)
    ajuste["x"] = int(x_edge)
    ajuste["y"] = int(y_edge)
    return ajuste


def measure_band(path, y0, y1, mc=None):
    """Measure every icon found in the band. Returns the list of measurements."""
    mc = mc or load_measure_corner()
    im = Image.open(path).convert("RGB")
    lum = np.asarray(im, dtype=float).mean(axis=2)
    results = []
    for (xa, xb) in find_icons(lum, y0, y1):
        # the icon's true left edge and its side, measured on a row well inside the body
        row = lum[y0 + int(0.6 * (y1 - y0))]
        body = np.where(row > 180.0)[0]
        body = body[(body >= xa - 4) & (body <= xb + 4)]
        if len(body) < 20:
            continue
        left = int(body.min())
        # the top edge: the first row of the icon
        top_edge = None
        for y in range(max(y0 - 20, 0), min(y0 + 60, lum.shape[0])):
            fila_y = lum[y]
            c = np.where(fila_y[left:left + 60] > 180.0)[0]
            if len(c) >= 20:
                top_edge = y
                break
        if top_edge is None:
            continue
        # THE SIDE IS MEASURED ON A ROW INSIDE THE BODY, and not as "the widest row". Under every
        # Launchpad icon there is a LIGHT LABEL with the app's name, so the widest light row in the
        # icon's column is the LABEL, not the icon: the first version took 112 px and 150 px for a
        # 96 px icon. A row 30 px into the body is inside the icon whatever the label does.
        fila_cuerpo = lum[min(top_edge + 30, lum.shape[0] - 1)]
        c = np.where(fila_cuerpo[max(left - 4, 0):left + 160] > 180.0)[0]
        side = int(c.max() - c.min() + 1) if len(c) >= 20 else 0
        if side < 40:
            continue
        m = measure_icon(lum, left, top_edge, side, mc)
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
    if fallos:
        for f in fallos:
            print(f"  FAIL {f}", file=sys.stderr)
        return 1
    print("self-test: ok")
    return 0


# ------------------------------------------------------------------------------------------------
# RENDER: our own drawing of the measured geometry (never a crop of Apple's pixels)
# ------------------------------------------------------------------------------------------------
def render(out_path, path=None, y0=40, y1=210):
    """Our OWN drawing of the measured geometry -- never a crop of Apple's pixels. The repository
    does not redistribute them, and what has to be read here is the PROFILE, not the artwork."""
    mc = load_measure_corner()
    if path is None:
        path = os.path.join(ROOT, "muestras", "Untitled3.png")
    measurements = measure_band(path, y0, y1, mc=mc)
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
    p.add_argument("--render")
    p.add_argument("--tol", type=float, default=2.0,
                   help="a fit with a bigger residual than this is reported but NOT averaged in")
    a = p.parse_args(argv)
    if a.self_test:
        return self_test()
    if a.render:
        return render(a.render)
    if a.image:
        y0, y1 = (int(v) for v in (a.grid or "40,210").split(","))
        mc = load_measure_corner()
        measurements = measure_band(a.image, y0, y1, mc=mc)
        if not measurements:
            print("no icons measured", file=sys.stderr)
            return 1
        print(f"{'x':>6} {'side':>5} {'R':>6} {'R/S':>6} {'err_circ':>9} {'err_figma':>9} {'s':>5}")
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

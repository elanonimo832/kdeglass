#!/usr/bin/env python3
"""
measure-controls.py — measures the macOS CONTROLS the kit's tokens do not carry.

WHY THIS EXISTS (M6, slices 4-6)
    `tokens/tokens-sizes.toml` carries the slider's knob (`[slider.knob_non_ticked_slider]`
    width/height) and the track's INSETS, and NOT the track's thickness; the checkbox and the
    radio have a size and a radius but no tick or dot geometry; and NOTHING in `tokens/` says
    what a SELECTED item looks like. The primary source for all of those is the same one M5 used:
    the user's own macOS screenshots in `muestras/` (gitignored -- what is versioned is the
    MEASUREMENT, never the pixels it came from).

    This tool measures, on a capture:
      * a BAR's thickness (a slider track) at the subpixel level,
      * a control's BOX: its subpixel edges, its size, and its corner radius,
      * the CAP HEIGHT of a text run, which is what fixes the capture's pixel-per-point SCALE,
      * the ROW PITCH of a list, from its separators,
      * the colour of a small patch.

    --self-test draws every one of those with a KNOWN value, reads it back with the SAME reader
    used on a photo, and prints the error. A number from a photo is a measurement only if the
    reader has been shown to work; without it the number is a coincidence (M5's own lesson).

THE CORNER FITTER IS IMPORTED, NOT COPIED
    `tools/measure-icon-geometry.py` already reads a corner profile out of pixels and fits a
    circle, the kit's own construction and a superellipse. This repository refuses to keep two
    copies of one formula (the shader and `simulate.py` had to be fixed together for exactly that
    reason), so the box reader below calls THAT module's `corner_profile` and `fit_all`.

WHAT THIS TOOL CANNOT DO, AND SAYS SO
    A 0.5 px border, a drop shadow, an animation and an antialiased colour are not figures this
    reader can produce honestly: where a measurement depends on the local background, and the
    background is a gradient or a shadow, the tool prints the dependence instead of a number.

USAGE
    python3 tools/measure-controls.py self-test
    python3 tools/measure-controls.py bar --image muestras/Untitled7.png --x 350 --span 180,200
    python3 tools/measure-controls.py knob --image muestras/Untitled7.png --axis x --at 191 \
        --span 380,440 --ink 410,191 --bg 380,191 --bg-far 430,191
    python3 tools/measure-controls.py box --image muestras/Untitled7.png --rect 500,545,600,640
    python3 tools/measure-controls.py cap --image muestras/Untitled7.png --cols 313,318 --rows 128,148
    python3 tools/measure-controls.py rows --image muestras/Untitled7.png --x 100 --span 170,320
    python3 tools/measure-controls.py color --image muestras/Untitled8.png --at 328,340 --box 3
    python3 tools/measure-controls.py render --out evidence/2026-10-16-m6-controls-measured.png
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
ICON_TOOL = os.path.join(HERE, "measure-icon-geometry.py")

# The bound the exact corner fit is asserted to hold across the four subpixel edge phases the
# self-test draws (radii 3, 5 and 8 px). It is the tool's own precision, and a measured corner is
# reported with an uncertainty ROUNDED UP from it, never down to it.
PHASE_TOL = 0.75


def load_icon_tool():
    """The corner reader/fitter lives in ONE place; this tool imports it."""
    spec = importlib.util.spec_from_file_location("measure_icon_geometry", ICON_TOOL)
    if spec is None or spec.loader is None:  # pragma: no cover
        raise RuntimeError(f"cannot import {ICON_TOOL}")
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


# --------------------------------------------------------------------------------------------------
# READING PIXELS
# --------------------------------------------------------------------------------------------------
def load_rgb(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=float)


def patch_color(im, x, y, box=2):
    """The MEDIAN colour of a small patch. A median and not a mean: a single antialiased pixel,
    a glyph edge or a highlight must not drag a token's colour."""
    ys = np.clip(np.arange(int(y) - box, int(y) + box + 1), 0, im.shape[0] - 1)
    xs = np.clip(np.arange(int(x) - box, int(x) + box + 1), 0, im.shape[1] - 1)
    return np.median(im[np.ix_(ys, xs)].reshape(-1, 3), axis=0)


def coverage(pixels, bg, ink):
    """How much of each pixel is INK, by projecting onto the bg->ink vector.

    One channel would do for a grey bar on a grey background and would lie for a blue accent on a
    grey one. The projection uses all three at once, and it is the same quantity the icon reader's
    0.5 crossing uses -- so a BAR and a CORNER are read by one definition of "edge", not two.
    """
    v = np.asarray(ink, dtype=float) - np.asarray(bg, dtype=float)
    denom = float(v @ v)
    if denom == 0.0:
        return np.zeros(len(pixels), dtype=float)
    return np.clip(((np.asarray(pixels, dtype=float) - bg) @ v) / denom, 0.0, 1.0)


def boundary_outward(cov, start, direction):
    """Where the ink ENDS, walking from `start` (inside the ink) towards `direction` (+1/-1).

    Pixel k covers [k, k+1). The walk goes out while the pixel is INK (coverage above the 0.5
    crossing the rest of this tool uses) and lands on the first pixel that is more background
    than ink; the boundary is then read from whichever of the two neighbouring pixels actually
    contains it:

        the landing pixel is partly inked   -> the boundary is inside it
        the landing pixel is empty          -> the boundary is inside the previous ink pixel,
                                               and if that one is full, exactly on its far edge

    WHY NOT "the first pixel whose coverage drops below 1", which is what this did first: a blue
    track's own colour drifts by a level or two along its length (the ink reference is one sample),
    so a FULLY inked pixel can come back at 0.996. Stopping there reported the Size slider's track
    as starting at x = 398 instead of x = 312 -- the walk gave up 86 px early, on a pixel that was
    simply a shade off the reference. Walking on the CROSSING LEVEL is immune to that drift.
    """
    i = int(start)
    n = len(cov)
    while 0 <= i < n and cov[i] > 0.5:
        i += direction
    if i < 0 or i >= n:
        return None
    if direction > 0:
        # the boundary is in pixel i if it holds any ink at all; otherwise in the one before it
        if cov[i] > 0.0:
            return float(i) + float(cov[i])
        return float(i - 1) + float(cov[i - 1])
    if cov[i] > 0.0:
        return float(i) + 1.0 - float(cov[i])
    return float(i + 1) + 1.0 - float(cov[i + 1])


def run_extent(cov, inside, lo, hi):
    """The subpixel [start, end] of the ink run that contains `inside`, in pixel coordinates."""
    a = boundary_outward(cov, inside, -1)
    b = boundary_outward(cov, inside, +1)
    if a is None or b is None:
        return None
    return a, b


def first_crossing(cov):
    """The LEFT/TOP boundary: the first pixel whose coverage reaches 0.5, and its own partial
    coverage. Inside a box with a tick or a hole, the first covered pixel IS the box's side."""
    idx = np.where(np.asarray(cov) >= 0.5)[0]
    if len(idx) == 0:
        return None
    i = int(idx[0])
    return float(i) + 1.0 - float(cov[i])


def last_crossing(cov):
    """The RIGHT/BOTTOM boundary, from the last pixel whose coverage reaches 0.5."""
    idx = np.where(np.asarray(cov) >= 0.5)[0]
    if len(idx) == 0:
        return None
    j = int(idx[-1])
    return float(j) + float(cov[j])


# --------------------------------------------------------------------------------------------------
# THE READERS
# --------------------------------------------------------------------------------------------------
def read_bar(im, axis, at, span, bg=None, ink=None):
    """A bar's subpixel extent across `axis`, and its thickness.

    `axis` is the direction ACROSS the bar: 'y' for a horizontal bar (the slider's track), 'x' for
    a vertical one. `at` is the coordinate ALONG the bar (a column for a horizontal bar). The
    background is sampled at both ends of the span and the ink at the pixel furthest from it,
    unless the caller passes them: a WHITE knob on a near-white background with a shadow under it
    is exactly the case where the automatic choice is wrong, and the caller has to say which two
    colours it means.
    """
    if axis == "y":
        prof = im[int(span[0]):int(span[1]), int(at)]
    else:
        prof = im[int(at), int(span[0]):int(span[1])]
    base = np.concatenate([prof[:3], prof[-3:]], axis=0)
    auto_bg = np.median(base, axis=0)
    if bg is None:
        bg = auto_bg
    if ink is None:
        d = np.abs(prof - bg).sum(axis=1)
        ink = prof[int(np.argmax(d))]
    cov = coverage(prof, bg, ink)
    inside = int(np.argmax(cov))
    a = boundary_outward(cov, inside, -1)
    b = boundary_outward(cov, inside, +1)
    # A SIDE THAT LEAVES THE SPAN IS REPORTED AS MISSING, not as a wrong number: a knob sitting on
    # two DIFFERENT backgrounds (the blue track on its left, the grey one on its right) has to be
    # read with one reference per edge, so each edge is measured in its own span and the other one
    # legitimately runs off the end.
    off = float(span[0])
    return {
        "bg": np.asarray(bg, dtype=float),
        "ink": np.asarray(ink, dtype=float),
        "start": None if a is None else off + a,
        "end": None if b is None else off + b,
        "thickness": None if (a is None or b is None) else b - a,
        "coverage": cov,
        "offset": off,
    }


def read_box(im, rect, corner="tl", rows=8, radius_min=1.0, radius_max=9.0, radius_step=0.25,
             bg=None, body=None, imported=True):
    """A control box: its four subpixel edges, its size, and its corner radius.

    The four edges are the FIRST and the LAST 0.5 crossing of a coverage ramp along the box's
    centre row and column -- the same definition of "edge" as the bar reader, and `measure-icon-
    geometry.py`'s own crossing value. The corner radius comes from that same module's profile and
    fitter, imported and not copied.

    WHY FIRST AND LAST, AND NOT ONE RUN THROUGH THE MIDDLE: a checkbox has a TICK inside it and an
    unchecked box has a HOLE where its interior is. A reader that walks outward from one interior
    pixel stops at the tick (the checked box measured 5.5 px wide) or at the interior's edge. The
    first and the last covered pixel of the centre line are the box's own two sides whatever is
    drawn inside it -- which is what the self-test's tick-shaped hole now checks.
    """
    ic = load_icon_tool()
    x0, x1, y0, y1 = (int(v) for v in rect)
    sub = im[y0:y1, x0:x1]
    if bg is None:
        # the ring just outside the rectangle: the left column and the right column
        ring = np.concatenate([sub[:, :2].reshape(-1, 3), sub[:, -2:].reshape(-1, 3)], axis=0)
        bg = np.median(ring, axis=0)
    # THE PROBE LINES ARE THE CENTRE OF THE INK'S OWN BOUNDING BOX, not the single furthest-from-
    # background pixel. Two earlier versions got that wrong and the self-test caught both: reusing
    # the row's argmax index as a COLUMN put the vertical probe on the box's left edge, inside the
    # corner arc (13.5 px tall, radius 1.0); and the 2D argmax put both probes on the box's
    # TOP-LEFT interior pixel, which is on the arc too (width 13.5, radius 7.75).
    dist = np.abs(sub - bg).sum(axis=2)
    m = dist > 0.5 * float(dist.max())
    ys_m, xs_m = np.nonzero(m)
    iy = int(round((ys_m.min() + ys_m.max()) / 2.0))
    ix = int(round((xs_m.min() + xs_m.max()) / 2.0))
    if body is None:
        # the most inked colour inside the box: the accent of a ticked box, the border of an
        # unticked one, and never the tick's white
        body = sub.reshape(-1, 3)[int(np.argmax(dist.reshape(-1)))]
    cov = coverage(sub[iy], bg, body)
    left = first_crossing(cov)
    right = last_crossing(cov)
    covc = coverage(sub[:, ix], bg, body)
    top = first_crossing(covc)
    bottom = last_crossing(covc)
    if None in (left, right, top, bottom):
        return None
    left, right = float(x0) + left, float(x0) + right
    top, bottom = float(y0) + top, float(y0) + bottom

    # THE CORNER, TWO WAYS, because the imported fitter's answer depends on where the box's edge
    # falls in the pixel grid and a 16 px checkbox with a 3-5 px corner is exactly where that shows.
    #
    #   (a) `fit`       -- `measure-icon-geometry.py`'s own reader and fitter, on the RECT CROP.
    #                      Kept for continuity with M5's published figures. Its crossing is the
    #                      0.5 crossing of a ramp between two neighbouring pixels, which sits
    #                      ~0.5 px OUTSIDE the true edge, and `fit_all` evaluates the model at
    #                      dy = row index. The two cancel only when the edge lands on a HALF
    #                      pixel (the phase its `--self-test` draws): then R = 5.0 comes back 5.00.
    #                      On an INTEGER edge nothing cancels, and the same drawn 5.0 comes back
    #                      2.30 (measured, this tool's own --self-test prints it).
    #   (b) `fit_exact` -- the same coverage definition as the BAR reader (a pixel's own coverage,
    #                      not an interpolation between two pixels), the inset measured from the
    #                      box's TRUE subpixel edge, and the model evaluated at the row's real
    #                      dy = row centre - edge. Over 31 synthetic boxes (radii 2.5..20 px,
    #                      edge phases 0.0..0.8) this recovers the drawn radius within 0.70 px
    #                      worst case, and the self-test below pins that.
    lum = sub.mean(axis=2)
    bg_l = float(np.mean(bg))
    body_l = float(np.mean(body))
    x_edge = (int(np.floor(left)) if corner in ("tl", "bl") else int(np.ceil(right))) - x0
    y_edge = (int(np.floor(top)) if corner in ("tl", "tr") else int(np.ceil(bottom))) - y0
    # `imported=False` skips the imported fitter, which is the expensive half (its figma family is
    # a search over 21 smoothings x every radius). The self-test's phase sweep uses it, because it
    # draws twelve boxes and only needs the exact answer; the CLI and the real measurements keep it.
    radios = ic.radius_grid(radius_min, radius_max, radius_step)
    if imported:
        profile = ic.corner_profile(lum, x_edge, y_edge, rows=rows, background=bg_l, body=body_l,
                                    corner=corner)
        ajuste = ic.fit_all(profile, ic.load_measure_corner(), radios=radios)
    else:
        profile, ajuste = None, None
    insets, dys = exact_corner_profile(sub, bg, body, corner, left - x0, right - x0,
                                       top - y0, bottom - y0, rows)
    exacto = fit_circle(insets, dys, radius_min, radius_max, radius_step)
    return {
        "left": left, "right": right, "top": top, "bottom": bottom,
        "width": right - left, "height": bottom - top,
        "bg": np.asarray(bg, dtype=float), "body": np.asarray(body, dtype=float),
        "profile": profile, "fit": ajuste, "x_edge": x_edge, "y_edge": y_edge,
        "insets": insets, "dys": dys, "fit_exact": exacto,
    }


def exact_corner_profile(crop, bg, body, corner, left, right, top, bottom, rows):
    """The corner's inset per row, from the pixel's OWN coverage and the box's TRUE subpixel edge.

    The rows start at the first row whose CENTRE is at or beyond the edge (a row whose centre is
    still outside the box has no inset to measure), and each row carries its real dy. That pair --
    exact inset and real dy -- is what makes the fit phase-independent; feeding the row INDEX as
    dy instead is what makes the imported reader's answer depend on where the edge sits.
    """
    insets, dys = [], []
    if corner in ("tl", "tr"):
        y_start, step = int(np.ceil(top - 0.5)), +1
        x_true = left if corner == "tl" else right
    else:
        y_start, step = int(np.floor(bottom - 0.5)), -1
        x_true = left if corner == "bl" else right
    for k in range(rows):
        y = y_start + step * k
        if y < 0 or y >= crop.shape[0]:
            break
        cov = coverage(crop[y], bg, body)
        # dy is measured from the corner's OWN horizontal edge: the TOP for a top corner and the
        # BOTTOM for a bottom one. Using one reference for both (the first version did) gave the
        # top-right corner dys of 15.5, 14.5, 13.5 ... against insets of 2.4, 1.3, 0.4 and a fit
        # with a 2.45 px residual -- a top corner measured as if it were upside down.
        dys.append((float(y) + 0.5 - top) if corner in ("tl", "tr")
                   else (bottom - (float(y) + 0.5)))
        if corner in ("tl", "bl"):
            a = first_crossing(cov)
            insets.append(np.nan if a is None else a - x_true)
        else:
            b = last_crossing(cov)
            insets.append(np.nan if b is None else x_true - b)
    return np.array(insets, dtype=float), np.array(dys, dtype=float)


def fit_circle(insets, dys, radius_min=0.5, radius_max=12.0, radius_step=0.05):
    """The best circular corner for an exact inset profile, with its residual.

    The MODEL is imported (`measure-icon-geometry.py`'s `inset_circle`), not copied; what is local
    is only the pairing of a row's inset with that row's own dy. The corner FAMILY is not fitted
    here: at a 3-8 px radius a circle, the kit's construction and a superellipse are the same
    curve to within a tenth of a pixel (M5's finding, and 10f-bis's), so a family would be an
    answer the pixels cannot carry.
    """
    ic = load_icon_tool()
    ok = ~np.isnan(np.asarray(insets, dtype=float))
    if int(ok.sum()) < 4:
        return None
    ins = np.asarray(insets, dtype=float)[ok]
    d = np.asarray(dys, dtype=float)[ok]
    mejor = None
    for R in np.arange(float(radius_min), float(radius_max) + 1e-9, float(radius_step)):
        e = float(np.max(np.abs(ic.inset_circle(d, R) - ins)))
        if mejor is None or e < mejor[0]:
            mejor = (e, float(R))
    return {"radius": mejor[1], "error": mejor[0], "rows": int(ok.sum()),
            "radios": (float(radius_min), float(radius_max))}


def read_cap(im, cols, rows, bg=None, ink=None):
    """The cap height of a text run, from the subpixel top of a flat-topped stem and its baseline.

    WHY THE CAP HEIGHT IS THE SCALE RULER: the HIG fixes the system font's sizes for control text
    (13 pt) and for the caption labels (10 pt), and `DESIGN-REFERENCES.md` records those as
    confirmed. A glyph's cap height is a FIXED fraction of its point size (SF Pro: capHeight/em =
    0.7046), so the same 13 pt text measures 9.16 px on a 1x capture and 10.47 px on a 1.15x one.
    That difference is what a capture can settle -- and it is settled by the SIZES the HIG gives,
    not by a token this project is trying to check, which would be circular.

    The caller passes a column band holding ONE stem that runs from the cap line to the baseline,
    and the row band around it. The edge is the same coverage crossing the rest of this tool uses.

    THE NORMALISATION IS PER COLUMN, and it took two wrong versions to get there. Normalising by
    the row with the most ink gave the 'D' of "Dock" 10 px instead of 9.3, because a cap's TOP
    STROKE is as wide as the letter while the stem is not: the row totals are not one rectangle's
    sides. A threshold on the columns counted a 40%-covered edge column as part of the stem and
    shrank the same figure by a third. What IS constant down a stem is the single column chosen
    here: its horizontal coverage. Dividing it out leaves the vertical coverage, which is the cap
    height -- and it no longer matters whether the stem is 1 px wide or 2.4, or whether the glyph
    has a bowl or a foot.
    """
    x0, x1 = (int(v) for v in cols)
    y0, y1 = (int(v) for v in rows)
    band = im[y0:y1, x0:x1]
    lum = band.mean(axis=2)
    if ink is None:
        flat = lum.reshape(-1)
        ink = float(np.percentile(flat, 2))
    if bg is None:
        bg = float(np.percentile(lum.reshape(-1), 98))
    cov2d = coverage(band.reshape(-1, 3), np.array([bg] * 3), np.array([ink] * 3))
    cov2d = cov2d.reshape(band.shape[:2])
    col = cov2d[:, int(np.argmax(cov2d.sum(axis=0)))]
    interior = col[col > 0.5 * col.max()]
    if interior.size == 0 or float(np.median(interior)) <= 0.0:
        return None
    per_row = np.clip(col / float(np.median(interior)), 0.0, 1.0)
    inside = int(np.argmax(col))
    a = boundary_outward(per_row, inside, -1)
    b = boundary_outward(per_row, inside, +1)
    if a is None or b is None:
        return None
    return {"top": float(y0) + a, "baseline": float(y0) + b, "cap_height": b - a,
            "bg": bg, "ink": ink, "stem_width_px": float(col.max() / np.median(interior)),
            "coverage": per_row}


def read_rows(im, x, span, gap=2):
    """The ROW PITCH of a list: the separators down a column, and the distances between them.

    A separator is a run of rows that differs from the row background. The pitch is the distance
    between consecutive separators, which is what a "row height" is for a list that draws them --
    and reporting the separators' own positions is what lets a reader check the figure instead of
    trusting it.
    """
    col = im[int(span[0]):int(span[1]), int(x)]
    lum = col.mean(axis=1)
    base = float(np.median(lum))
    dark = lum < base - 4.0
    runs, start = [], None
    for i, v in enumerate(dark):
        if v and start is None:
            start = i
        if not v and start is not None:
            if i - start <= gap:
                runs.append((start, i - 1))
            start = None
    if start is not None and len(dark) - start <= gap:
        runs.append((start, len(dark) - 1))
    centres = [float(span[0]) + (a + b) / 2.0 for a, b in runs]
    pitches = [round(centres[i + 1] - centres[i], 2) for i in range(len(centres) - 1)]
    return {"background": base, "separators": [round(c, 2) for c in centres], "pitches": pitches}


# --------------------------------------------------------------------------------------------------
# SELF-TEST: every reader, on a value it was given
# --------------------------------------------------------------------------------------------------
def draw_scene(ss=8):
    """A synthetic control strip whose geometry is KNOWN, drawn with supersampling so its edges
    are antialiased the way a real capture's are. Returns the image and the values."""
    W, H = 220, 140
    n = ss
    ys, xs = np.mgrid[0:H * n, 0:W * n]
    px = (xs + 0.5) / n - 0.5
    py = (ys + 0.5) / n - 0.5

    bg = np.array([247.0, 247.0, 247.0])
    hi = np.tile(bg, (H * n, W * n, 1))

    def paint(mask, color):
        """Composites the mask into the SUPERSAMPLED buffer at full resolution; the single
        downsample at the end is what turns the hard high-resolution boundary into an antialiased
        edge. A second paint therefore cannot rescale an already-downsampled image (which is what
        the first version did, and a reshape error is how it was caught)."""
        cov = mask.astype(float)[..., None]
        hi[:] = hi * (1.0 - cov) + np.asarray(color, dtype=float) * cov

    known = {}

    # 1. A BAR: 6.0 px of track from x=10..90, whose vertical centre is y=20.5 -> rows 18..23.
    bar_top, bar_bottom = 18.0, 24.0
    m = (px >= 10) & (px < 90) & (py >= bar_top) & (py < bar_bottom)
    paint(m, [0, 122, 255])
    known["bar_thickness"] = bar_bottom - bar_top

    # 2. A BOX: 16 x 16 with a 5.0 px corner radius, top-left at (10, 40).
    bx, by, side, radius = 10.0, 40.0, 16.0, 5.0
    cx, cy = bx + radius, by + radius
    d = np.sqrt((px - cx) ** 2 + (py - cy) ** 2)
    m = (((px >= bx + radius) & (px < bx + side) & (py >= by) & (py < by + side))
         | ((px >= bx) & (px < bx + side) & (py >= by + radius) & (py < by + side))
         | (d <= radius))
    m &= (px >= bx) & (px < bx + side) & (py >= by) & (py < by + side)
    paint(m, [0, 122, 255])
    known["box_side"] = side
    known["box_radius"] = radius
    known["box_rect"] = (bx, by)

    # 2b. A TICK INSIDE IT, which is a HOLE in the ink. This is the case that caught the reader:
    # the centre row of a real checked checkbox crosses its own tick, and a reader that walks out
    # from one interior pixel stopped there and called a 16 px box 5.5 px wide.
    m = (px >= bx + 5) & (px < bx + 11) & (py >= by + 5) & (py < by + 11)
    paint(m, [255, 255, 255])

    # 3. A KNOB: a white 20 x 16 box with a 8 px corner radius above the bar, at (120, 14).
    kx, ky, kw, kh, kr = 120.0, 13.0, 20.0, 16.0, 8.0
    cx, cy = kx + kr, ky + kr
    d = np.sqrt((px - cx) ** 2 + (py - cy) ** 2)
    m = (((px >= kx + kr) & (px < kx + kw) & (py >= ky) & (py < ky + kh))
         | ((px >= kx) & (px < kx + kw) & (py >= ky + kr) & (py < ky + kh))
         | (d <= kr))
    m &= (px >= kx) & (px < kx + kw) & (py >= ky) & (py < ky + kh)
    paint(m, [255, 255, 255])
    known["knob_width"] = kw
    known["knob_height"] = kh

    # 4. TEXT: a flat-topped stem 2 px wide and 9.3 px tall, top at y=90, in the label's ink.
    m = (px >= 150) & (px < 152) & (py >= 90) & (py < 99.3)
    paint(m, [60, 60, 60])
    known["cap_height"] = 9.3

    # 5. A LIST: three separators 25 px apart, 1 px tall, at y=100, 125... (the last is off-canvas
    #    for a 120 px canvas, so the list reader is checked on the two that fit).
    for i, y in enumerate((100.0, 125.0)):
        m = (px >= 4) & (px < 60) & (py >= y) & (py < y + 1.0)
        paint(m, [200, 200, 200])
    known["row_pitch"] = 25.0

    img = hi.reshape(H, n, W, n, 3).mean(axis=(1, 3))
    return img, known


def draw_phase_box(radius, side=16.0, x0=12.0, y0=12.0, ss=8, pad=14):
    """A rounded box whose edges sit on INTEGER pixel coordinates, in the pixel-index convention
    (pixel i covers [i, i+1)). The tool's scene draws at a half-pixel offset on purpose -- that is
    the phase the imported corner fitter was calibrated on -- so the phase that breaks it needs a
    box of its own rather than a second copy of the scene."""
    W, H = int(side + 2 * pad), int(side + 2 * pad)
    n = ss
    ys, xs = np.mgrid[0:H * n, 0:W * n]
    px = (xs + 0.5) / n
    py = (ys + 0.5) / n
    cx, cy = x0 + radius, y0 + radius
    d = np.sqrt((px - cx) ** 2 + (py - cy) ** 2)
    m = (((px >= x0 + radius) & (px < x0 + side) & (py >= y0) & (py < y0 + side))
         | ((px >= x0) & (px < x0 + side) & (py >= y0 + radius) & (py < y0 + side))
         | (d <= radius))
    m &= (px >= x0) & (px < x0 + side) & (py >= y0) & (py < y0 + side)
    hi = np.tile(np.array([247.0, 247.0, 247.0]), (H * n, W * n, 1))
    cov = m.astype(float)[..., None]
    hi = hi * (1.0 - cov) + np.array([0.0, 122.0, 255.0]) * cov
    return hi.reshape(H, n, W, n, 3).mean(axis=(1, 3))


def self_test():
    ic = load_icon_tool()
    img, known = draw_scene()
    fallos = []

    def check(name, got, want, tol=0.35):
        if got is None:
            fallos.append(f"{name}: the reader produced nothing")
            print(f"  FAIL {name}: no reading")
            return
        e = abs(got - want)
        print(f"  self-test {name:<14} -> {got:8.3f}  (drawn {want:8.3f}, error {e:.3f} px)")
        if e > tol:
            fallos.append(f"{name}: read {got:.3f}, drawn {want:.3f}")

    # the bar: a column through it, with the colours stated
    b = read_bar(img, "y", 40, (10, 32))
    if b is None:
        fallos.append("bar: no reading")
    else:
        check("bar_thickness", b["thickness"], known["bar_thickness"], 0.05)

    # the box: its sides from the middle row/column, and its corner radius from the fitter
    r = read_box(img, (0, 40, 30, 66))
    if r is None:
        fallos.append("box: no reading")
    else:
        check("box_width", r["width"], known["box_side"], 0.15)
        check("box_height", r["height"], known["box_side"], 0.15)
        check("box_radius", r["fit"]["circle"]["radius"], known["box_radius"], 0.35)
        # THE EXACT FIT ON THE SAME BOX. The scene draws it at a HALF-pixel offset (the convention
        # its own renderer uses), which is exactly the phase the imported fitter was calibrated
        # on; that is why the two agree here. The case where they do NOT agree has its own boxes.
        check("box_radius_exact", r["fit_exact"]["radius"], known["box_radius"], 0.35)

    # THE PHASE TEST, and it is the reason this tool does not simply import the fitter's answer.
    # Rounded boxes of a KNOWN radius are drawn with their edges at four different subpixel
    # PHASES. The imported fitter is accurate only at the half-pixel phase its `--self-test`
    # draws; the exact reader is accurate at all of them, within the bound asserted here -- which
    # is therefore the bound a real capture's corner carries, and the number the token's
    # uncertainty is rounded up from.
    peor, peor_caso = 0.0, ""
    for fase in (0.0, 0.25, 0.5, 0.75):
        for radio in (3.0, 5.0, 8.0):
            img_f = draw_phase_box(radio, x0=12.0 + fase, y0=12.0 + fase)
            rf = read_box(img_f, (0, 44, 0, 44), corner="tl", rows=9, radius_min=0.5,
                          radius_max=12, radius_step=0.05, imported=False)
            if rf is None or rf["fit_exact"] is None:
                fallos.append(f"phase {fase} R={radio}: no reading")
                continue
            got = rf["fit_exact"]["radius"]
            e = abs(got - radio)
            if e > peor:
                peor, peor_caso = e, f"phase {fase} R={radio}"
            print(f"  self-test phase {fase:<4} drawn R={radio:<4} -> exact {got:7.2f}  "
                  f"(error {e:.2f})")
            if e > PHASE_TOL:
                fallos.append(f"phase {fase} R={radio}: exact fit read {got}, drawn {radio}")
    print(f"  self-test worst phase error {peor:.2f} px ({peor_caso}); the bound asserted is "
          f"{PHASE_TOL:.2f} px")

    # THE SAME BOXES, THROUGH THE IMPORTED FITTER, so the contrast is printed and not only
    # asserted. A coarse radius grid keeps this cheap: the imported fitter's figma family is a
    # search over every radius x 21 smoothings, and only its BLIND SPOT needs to be visible here.
    for fase, radio in ((0.0, 5.0), (0.5, 5.0)):
        img_f = draw_phase_box(radio, x0=12.0 + fase, y0=12.0 + fase)
        rf = read_box(img_f, (0, 44, 0, 44), corner="tl", rows=9, radius_min=0.5,
                      radius_max=12, radius_step=0.5)
        imp = rf["fit"]["circle"]["radius"] if rf and rf["fit"] else float("nan")
        print(f"  self-test imported fitter, drawn R={radio}, edge at .{int(fase*100)} -> {imp:7.2f}")
        if fase == 0.5 and abs(imp - radio) > 0.5:
            fallos.append(f"the imported fitter stopped working at its own phase: {imp} for {radio}")

    # the knob: white on a 247 background -- the low-contrast case, WITH the colours stated
    k = read_bar(img, "x", 20, (110, 150), bg=[247, 247, 247], ink=[255, 255, 255])
    if k is None:
        fallos.append("knob: no reading")
    else:
        check("knob_width", k["thickness"], known["knob_width"], 0.2)
    k = read_bar(img, "y", 130, (5, 35), bg=[247, 247, 247], ink=[255, 255, 255])
    if k is None:
        fallos.append("knob height: no reading")
    else:
        check("knob_height", k["thickness"], known["knob_height"], 0.2)

    # the text: a flat-topped stem, read by the cap reader
    c = read_cap(img, (148, 154), (85, 105))
    if c is None:
        fallos.append("cap: no reading")
    else:
        check("cap_height", c["cap_height"], known["cap_height"], 0.1)

    # the list: its separators and the pitch between them
    rr = read_rows(img, 30, (90, 139))
    if len(rr["pitches"]) >= 1:
        print(f"  self-test row_pitch      -> {rr['pitches'][0]:8.3f}  (drawn "
              f"{known['row_pitch']:8.3f}, separators at {rr['separators']})")
        if abs(rr["pitches"][0] - known["row_pitch"]) > 0.5:
            fallos.append(f"row_pitch: read {rr['pitches'][0]}, drawn {known['row_pitch']}")
    else:
        fallos.append(f"row_pitch: found {rr['separators']}, expected two separators")

    if fallos:
        for f in fallos:
            print(f"  FAIL {f}", file=sys.stderr)
        return 1
    print("self-test: ok")
    return 0


# --------------------------------------------------------------------------------------------------
# EVIDENCE: OUR OWN drawing of the measured geometry (never a crop of Apple's pixels)
# --------------------------------------------------------------------------------------------------
def render(out_path, values):
    """Draws the measured figures as OUR OWN schematic. No Apple pixel is copied: the repository
    versions the measurement, and a drawing of it, never the screenshot it came from."""
    W, H = 900, 380
    img = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.text((24, 16), "M6 - the controls the kit does not carry, measured from the user's screenshots",
           fill=(20, 20, 20))
    d.text((24, 34), "each figure is our own drawing at the measured size, in pixels of the capture",
           fill=(90, 90, 90))

    # the slider: track thickness and knob, at 6x so a 6 px track is visible
    s = 6
    ox, oy = 40, 80
    track = int(round(values["track_px"] * s))
    knob_w = int(round(values["knob_w_px"] * s))
    knob_h = int(round(values["knob_h_px"] * s))
    d.text((ox, oy - 18), f"slider: track {values['track_px']:.1f} px, knob "
                          f"{values['knob_w_px']:.1f} x {values['knob_h_px']:.1f} px", fill=(20, 20, 20))
    d.rectangle([ox, oy + (knob_h - track) // 2, ox + 260, oy + (knob_h - track) // 2 + track],
                fill=(0, 122, 255))
    d.rounded_rectangle([ox + 90, oy, ox + 90 + knob_w, oy + knob_h], radius=knob_h // 2,
                        fill=(255, 255, 255), outline=(200, 200, 200))

    # the checkbox: box, corner radius and the tick. The UNCHECKED box is drawn the way the
    # capture draws it -- a SOLID grey fill (#DFDFDF), not an outline -- because that is one of the
    # findings: a drawing that showed a hollow box would be arguing with its own measurement.
    ox = 400
    box = int(round(values["checkbox_px"] * s))
    r = int(round(values["checkbox_radius_px"] * s))
    d.text((ox, oy - 18), f"checkbox: {values['checkbox_px']:.1f} px, radius "
                          f"{values['checkbox_radius_px']:.1f} px; unchecked is a SOLID grey fill",
           fill=(20, 20, 20))
    d.rounded_rectangle([ox, oy, ox + box, oy + box], radius=r, fill=(0, 122, 255))
    d.line([(ox + box * 0.25, oy + box * 0.52), (ox + box * 0.43, oy + box * 0.70),
            (ox + box * 0.75, oy + box * 0.30)], fill=(255, 255, 255), width=max(1, box // 8))
    d.rounded_rectangle([ox + box + 30, oy, ox + 2 * box + 30, oy + box],
                        radius=int(round(values["checkbox_radius_unchecked_px"] * s)),
                        fill=(223, 223, 223))

    # the selection: the cell rectangle and the label capsule, at the sizes the capture gave
    ox, oy = 40, 172
    s2 = 1.0
    cell_w = int(round(values["cell_w_px"] * s2))
    cell_h = int(round(values["cell_h_px"] * s2))
    d.text((ox, oy - 16), f"Finder selection: cell {values['cell_w_px']:.0f} x {values['cell_h_px']:.0f} px, "
                          f"radius {values['selection_radius_px']:.1f} px; label capsule "
                          f"{values['label_w_px']:.1f} x {values['label_h_px']:.1f} px", fill=(20, 20, 20))
    d.rounded_rectangle([ox, oy, ox + cell_w, oy + cell_h],
                        radius=int(round(values["selection_radius_px"] * s2)), fill=(226, 227, 228))
    pill_w = int(round(values["label_w_px"] * s2)); pill_h = int(round(values["label_h_px"] * s2))
    pill_x = ox + (cell_w - pill_w) // 2
    pill_y = oy + cell_h + 2
    d.rounded_rectangle([pill_x, pill_y, pill_x + pill_w, pill_y + pill_h],
                        radius=int(round(values["label_radius_px"] * s2)), fill=(0, 100, 225))
    d.text((pill_x + 6, pill_y + max(0, pill_h // 2 - 6)), "selected", fill=(255, 255, 255))

    img.save(out_path)
    print(f"wrote {out_path}")
    return 0


# --------------------------------------------------------------------------------------------------
def fmt_color(c):
    return "#%02X%02X%02X" % tuple(int(round(v)) for v in c)


def main(argv=None):
    p = argparse.ArgumentParser(description="Measure the macOS controls a capture shows.")
    sub = p.add_subparsers(dest="cmd")

    s = sub.add_parser("self-test")
    s = sub.add_parser("bar")
    s.add_argument("--image", required=True)
    s.add_argument("--axis", default="y", choices=("x", "y"))
    s.add_argument("--at", type=int, required=True, help="the coordinate ALONG the bar")
    s.add_argument("--span", required=True, help="across the bar, 'a,b'")
    s.add_argument("--bg", help="the background colour, 'r,g,b' (a shadow makes the auto one lie)")
    s.add_argument("--ink", help="the ink colour, 'r,g,b'")

    s = sub.add_parser("knob")
    s.add_argument("--image", required=True)
    s.add_argument("--axis", default="x", choices=("x", "y"))
    s.add_argument("--at", type=int, required=True)
    s.add_argument("--span", required=True)
    s.add_argument("--bg", required=True, help="the background just OUTSIDE this edge")
    s.add_argument("--ink", required=True, help="the knob's own colour")

    s = sub.add_parser("box")
    s.add_argument("--image", required=True)
    s.add_argument("--rect", required=True, help="x0,x1,y0,y1 around the box")
    s.add_argument("--corner", default="tl", choices=("tl", "tr", "bl", "br"))
    s.add_argument("--rows", type=int, default=8)
    s.add_argument("--radius-min", type=float, default=1.0)
    s.add_argument("--radius-max", type=float, default=9.0)
    s.add_argument("--radius-step", type=float, default=0.25)

    s = sub.add_parser("cap")
    s.add_argument("--image", required=True)
    s.add_argument("--cols", required=True, help="the column band holding ONE stem")
    s.add_argument("--rows", required=True, help="the row band around it")

    s = sub.add_parser("rows")
    s.add_argument("--image", required=True)
    s.add_argument("--x", type=int, required=True)
    s.add_argument("--span", required=True)
    s.add_argument("--gap", type=int, default=2)

    s = sub.add_parser("color")
    s.add_argument("--image", required=True)
    s.add_argument("--at", required=True, help="x,y")
    s.add_argument("--box", type=int, default=2)

    s = sub.add_parser("render")
    s.add_argument("--out", required=True)
    s.add_argument("--track", type=float, default=6.0)
    s.add_argument("--knob-w", type=float, default=19.8)
    s.add_argument("--knob-h", type=float, default=16.0)
    s.add_argument("--checkbox", type=float, default=16.0)
    s.add_argument("--checkbox-radius", type=float, default=4.6)
    s.add_argument("--checkbox-radius-unchecked", type=float, default=5.85)
    s.add_argument("--selection-radius", type=float, default=14.0)
    s.add_argument("--cell-w", type=float, default=144.0)
    s.add_argument("--cell-h", type=float, default=145.0)
    s.add_argument("--label-w", type=float, default=79.0)
    s.add_argument("--label-h", type=float, default=16.4)
    s.add_argument("--label-radius", type=float, default=5.7)

    a = p.parse_args(argv)
    if a.cmd in (None, "self-test"):
        return self_test()

    if a.cmd == "render":
        return render(a.out, {"track_px": a.track, "knob_w_px": a.knob_w, "knob_h_px": a.knob_h,
                              "checkbox_px": a.checkbox, "checkbox_radius_px": a.checkbox_radius,
                              "checkbox_radius_unchecked_px": a.checkbox_radius_unchecked,
                              "selection_radius_px": a.selection_radius,
                              "cell_w_px": a.cell_w, "cell_h_px": a.cell_h,
                              "label_w_px": a.label_w, "label_h_px": a.label_h,
                              "label_radius_px": a.label_radius})

    im = load_rgb(a.image)

    if a.cmd in ("bar", "knob"):
        span = tuple(int(v) for v in a.span.split(","))
        bg = tuple(float(v) for v in a.bg.split(",")) if a.bg else None
        ink = tuple(float(v) for v in a.ink.split(",")) if a.ink else None
        # a 'knob' is a bar read with the colours STATED; the reading is identical
        r = read_bar(im, a.axis, a.at, span, bg=bg, ink=ink)
        if r is None:
            print("no edge found: the span, the axis or the colours are wrong", file=sys.stderr)
            return 1
        print(f"  {a.cmd}: axis={a.axis} at={a.at} span={span}")
        print(f"    background   {fmt_color(r['bg'])}")
        print(f"    ink          {fmt_color(r['ink'])}")
        start = "off the span" if r["start"] is None else f"{r['start']:.3f} px"
        end = "off the span" if r["end"] is None else f"{r['end']:.3f} px"
        print(f"    start        {start}")
        print(f"    end          {end}")
        if r["thickness"] is None:
            print("    EXTENT       only one edge in this span   <- run it again from the other side")
        else:
            print(f"    EXTENT       {r['thickness']:.3f} px   <- the measured figure")
        return 0

    if a.cmd == "box":
        r = read_box(im, tuple(int(v) for v in a.rect.split(",")), corner=a.corner, rows=a.rows,
                     radius_min=a.radius_min, radius_max=a.radius_max, radius_step=a.radius_step)
        if r is None:
            print("no box edge found: check --rect", file=sys.stderr)
            return 1
        print(f"  box: rect={a.rect} corner={a.corner}")
        print(f"    background   {fmt_color(r['bg'])}   body {fmt_color(r['body'])}")
        print(f"    left {r['left']:.3f}  right {r['right']:.3f}  ->  WIDTH  {r['width']:.3f} px")
        print(f"    top  {r['top']:.3f}  bottom {r['bottom']:.3f}  ->  HEIGHT {r['height']:.3f} px")
        print(f"    corner profile (imported reader, edge x={r['x_edge']} y={r['y_edge']}): "
              f"{np.array2string(r['profile'], precision=2)}")
        for fam in ("circle", "figma", "superellipse"):
            f = r["fit"][fam]
            extra = (f" s={f['smoothing']:.2f}" if fam == "figma"
                     else (f" n={f['exponent']:.2f}" if fam == "superellipse" else ""))
            print(f"    {fam:<13} R = {f['radius']:.2f} px  residual {f['error']:.2f} px{extra}")
        print(f"    radii searched {r['fit']['radios']}, rows fitted {r['fit']['rows']}")
        return 0

    if a.cmd == "cap":
        r = read_cap(im, tuple(int(v) for v in a.cols.split(",")),
                     tuple(int(v) for v in a.rows.split(",")))
        if r is None:
            print("no stem found: check --cols/--rows", file=sys.stderr)
            return 1
        print(f"  cap: cols={a.cols} rows={a.rows}  bg={r['bg']:.1f} ink={r['ink']:.1f} "
              f"stem {r['stem_width_px']:.2f} px wide")
        print(f"    top edge     {r['top']:.3f} px")
        print(f"    baseline     {r['baseline']:.3f} px")
        print(f"    CAP HEIGHT   {r['cap_height']:.3f} px")
        return 0

    if a.cmd == "rows":
        r = read_rows(im, a.x, tuple(int(v) for v in a.span.split(",")), gap=a.gap)
        print(f"  rows: x={a.x} span={a.span}  background {r['background']:.1f}")
        print(f"    separators   {r['separators']}")
        print(f"    pitches      {r['pitches']}")
        return 0

    if a.cmd == "color":
        x, y = (int(v) for v in a.at.split(","))
        c = patch_color(im, x, y, box=a.box)
        print(f"  color: at {x},{y} box {a.box}  ->  {fmt_color(c)}  "
              f"(rgb {int(c[0])},{int(c[1])},{int(c[2])})")
        return 0

    p.error("unknown subcommand")
    return 2


if __name__ == "__main__":
    sys.exit(main())

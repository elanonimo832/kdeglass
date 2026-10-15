#!/usr/bin/env python3
"""Simulates the band's maths in Python, so a change can be looked at without a relogin.

WHY THIS EXISTS. Every iteration on this effect has cost the user a session: build, install,
log out, log in, look, screenshot. That is a minute of their time and a real chance of losing
their place, and it is why three defects in the same mechanism survived three rounds. The band's
arithmetic is not the GPU's: it is a frost, a median, a coverage estimate and two mixes, all of
which numpy can do. With two screenshots -- the window's title strip with the effect OFF, and the
same region of the desktop with the window out of the way -- this reproduces what the effect will
do, and a wrong idea costs seconds instead of a session.

    # with the effect off, capture the window's title strip:
    spectacle -b -n -o /tmp/titulo.png          # then crop it to the strip
    # move the window away and capture the same region of the desktop:
    spectacle -b -n -o /tmp/fondo.png           # same crop

    python3 simulate.py --window /tmp/titulo.png --backdrop /tmp/fondo.png --out /tmp/banda.png
    python3 simulate.py --self-test

Every knob the effect reads is an option with the same name, so a value can be tried here first:

    python3 simulate.py ... --GlassAlpha 0.25 --Rim 0.2 --MaterialBoost 1.6

The two inputs must be the SAME crop of the SAME region, one with the window and one without.
`--self-test` checks the model against the two cases whose answer is known by definition: with
GlassAlpha 0 the band is the frosted backdrop, and with GlassAlpha 1 it is the bar's own tone.
"""
import argparse
import math
import pathlib
import sys

import numpy as np
from PIL import Image

# The defaults are the effect's own, and they are read from the source so the two cannot drift.
#
# ANCHORED TO THIS FILE, NOT TO THE WORKING DIRECTORY. It used to be "src/glass.h", which resolves
# only when the tool is run from effect-kwin/ -- from anywhere else the open fails, the except below
# swallows it, and every knob silently falls back to the hardcoded number next to it. That cost me
# three contradictory measurements in a row before I found it: the header said 1.3 and the tool was
# using 0.75. A default that depends on WHERE you stand is worse than no default.
HEADER = str(pathlib.Path(__file__).resolve().parent / "src" / "glass.h")


def defaults_from_source(ruta=HEADER):
    """Reads `k<Name> = <value>f` from the header, so a default has ONE home."""
    valores = {}
    try:
        with open(ruta, encoding="utf-8") as f:
            for linea in f:
                linea = linea.strip()
                if not linea.startswith("static constexpr float k"):
                    continue
                nombre = linea.split("k", 1)[1].split(" =")[0]
                valor = linea.split("=", 1)[1].strip().split("f")[0]
                valores[nombre] = float(valor)
    except OSError as e:
        # LOUD, not silent: a header that cannot be read means every default below is a stale
        # hardcoded guess, and pretending otherwise is how three measurements went wrong.
        print(f"warning: could not read {ruta} ({e}); using the hardcoded fallbacks", file=sys.stderr)
    return valores


DEFAULTS = defaults_from_source()
GLASS_ALPHA = DEFAULTS.get("GlassAlpha", 0.25)
BACKGROUND_RADIUS = int(DEFAULTS.get("BackgroundRadius", 16))
MATERIAL_BOOST = DEFAULTS.get("MaterialBoost", 1.20)
MATERIAL_GAIN = DEFAULTS.get("MaterialGain", 1.60)
REFRACTION = DEFAULTS.get("Refraction", 3.0)
RIM_COLOUR = DEFAULTS.get("RimColour", 1.8)
SPECULAR = DEFAULTS.get("Specular", 0.7)
SPECULAR_WIDTH = DEFAULTS.get("SpecularWidth", 2.0)
RIM = DEFAULTS.get("Rim", 0.20)
RIM_WIDTH = DEFAULTS.get("RimWidth", 12.0)
# How far the BEND reaches inward, in screen pixels. Separate from RimWidth, which sets the
# rim's own width: the bend and the rim are different things, and sharing one number meant
# widening the bend widened the rim.
REFRACTION_REACH = DEFAULTS.get("RefractionReach", 24.0)
CORNER_RADIUS = DEFAULTS.get("CornerRadius", 20.0)
FROST_RADIUS = DEFAULTS.get("FrostRadius", 6.0)
CHROME_LOW = DEFAULTS.get("ChromeLow", 0.06)
INNER_SCALE = 0.375          # the kit's frost 6/16/16, as in the shader
LUMA = np.array([0.2126, 0.7152, 0.0722])
RADIUS_CAP = 2               # bilinear minification by 2 is a true box; by 4 it aliases


def luma(img):
    return img @ LUMA


def reduce_box(img, factor):
    """The capture: a GL_LINEAR blit minifying by `factor` (2 is a true 2x2 box)."""
    if factor <= 1:
        return img
    h, w = img.shape[:2]
    h2, w2 = h // factor, w // factor
    recortada = img[:h2 * factor, :w2 * factor]
    return recortada.reshape(h2, factor, w2, factor, 3).mean(axis=(1, 3))


def bilinear(img, ys, xs):
    """Samples `img` at floating point (ys, xs), clamped to its edges -- as the sampler does."""
    h, w = img.shape[:2]
    ys = np.clip(ys, 0, h - 1)
    xs = np.clip(xs, 0, w - 1)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    y1 = np.clip(y0 + 1, 0, h - 1)
    x1 = np.clip(x0 + 1, 0, w - 1)
    fy = (ys - y0)[..., None]
    fx = (xs - x0)[..., None]
    return (img[y0, x0] * (1 - fy) * (1 - fx) + img[y1, x0] * fy * (1 - fx)
            + img[y0, x1] * (1 - fy) * fx + img[y1, x1] * fy * fx)


def frost(backdrop, radius, factor, shift_y=None, shift_x=None):
    """The two scales of the kit's frost, over the reduced capture, as the shader does it.

    The output is at FULL size: the shader computes it per screen fragment by sampling the
    reduced texture, whose taps are `radius / factor` texels apart. Getting that wrong (leaving
    the result small) is what the first version of this file did, and it is also the difference
    between "the capture is averaged" and "the capture is sampled".
    """
    small = reduce_box(backdrop, factor)
    h, w = backdrop.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    # where this fragment is, in the reduced texture's own coordinates
    y0, x0 = yy / factor, xx / factor
    if shift_y is not None:                      # the bend, applied BEFORE the frost as in the shader
        y0 = y0 + shift_y / factor
    if shift_x is not None:
        x0 = x0 + shift_x / factor
    # FOUR LEVELS, equal weight each: the coarsest carries the spread and the finest (r/8 = 2 px)
    # averages a letter's stem. Measured: the surviving contrast of backdrop text fell sharply with
    # this, where raising the radius alone did nothing (100% at 16 px, 98% at 40 px).
    total = np.zeros_like(backdrop)
    for escala, peso in ((radius, 1.0), (radius * 0.5, 1.0), (radius * 0.25, 1.0),
                         (radius * 0.125, 6.0)):
        paso = escala / factor
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                total += peso * bilinear(small, y0 + dy * paso, x0 + dx * paso)
    return np.clip(total / 81.0, 0, 1)


def tone(window, radius):
    """The bar's own colour: a VERTICAL median of five, clamped inside the strip.

    Vertical because this theme's chrome is wide and thin, which two rounds of ghosting taught;
    a median because a blur of the bar still contains the chrome, displaced by the radius.
    """
    h, w = window.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    lados = [np.clip(yy + dy * radius, 0.0, h - 1.0) for dy in (0, -1, 1, -2, 2)]
    muestras = np.stack([bilinear(window, y, xx) for y in lados])
    return np.median(muestras, axis=0)


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-6), 0, 1)
    return t * t * (3 - 2 * t)


def clothoid_corner_cf(radius, smoothing, samples=96):
    """The G2 corner as a polyline in the corner's own frame, from (p, 0) on the TOP edge to
    (0, p) on the LEFT one, plus the edge offset `p`.

    A CLOTHOID (Euler spiral): the curvature rises LINEARLY from 0 at the straight edge to 1/R at
    the arc -- kappa(s) = s/(R*L) -- and the arc keeps its measure `m = 90*(1-s)`. It is therefore
    curvature-continuous BY CONSTRUCTION, which is what the user asked for after seeing the shade
    break at an angle: measured with measure-corner.py the clothoid overshoots the arc by +0.0% and
    has no local maximum above it, where the Figma construction it replaces overshot by +46.9%.
    The transition's turn is fixed by the arc (dtheta = (pi/2 - m)/2), which fixes its length
    L = 2*R*dtheta, and the corner's symmetry about x = y fixes where it meets the straight edge.
    """
    R = float(radius)
    # THE ARC MEASURE STAYS FIGMA'S `90*(1-s)`: with s = 0.6 that is 36 degrees, the value the
    # current screen was tuned against. Choosing m is taste and comparison with the sample, not
    # curvature, so it is held fixed here to change ONE thing at a time.
    m = math.radians(90.0 * (1.0 - float(smoothing)))
    dtheta = (math.pi / 2.0 - m) / 2.0
    L = 2.0 * R * dtheta
    n = max(8, int(samples) // 2)
    if L <= 1e-12:
        # s = 0: the transition has NO length and the corner IS the circular arc. Return it directly
        # instead of dividing by zero in the heading below.
        alphas = np.linspace(-math.pi / 2.0, -math.pi, max(4, int(samples)) + 1)
        arc = np.stack([R + R * np.cos(alphas), R + R * np.sin(alphas)], axis=1)
        return arc, R
    s = np.linspace(0.0, L, n + 1)
    theta = math.pi - (s * s) / (2.0 * R * L)   # heading: from 180 deg (-x), turning toward +y
    ds = L / n
    xs = np.zeros(n + 1)
    ys = np.zeros(n + 1)
    for i in range(1, n + 1):
        xs[i] = xs[i - 1] + ds * 0.5 * (math.cos(theta[i - 1]) + math.cos(theta[i]))
        ys[i] = ys[i - 1] + ds * 0.5 * (math.sin(theta[i - 1]) + math.sin(theta[i]))
    # The arc's centre must sit on the diagonal for the corner to be symmetric, and that fixes the
    # edge offset p. The normal toward the centre is perpendicular to the end heading.
    nx, ny = math.cos(theta[-1] + math.pi / 2.0), math.sin(theta[-1] + math.pi / 2.0)
    if nx + ny < 0.0:
        nx, ny = -nx, -ny
    p = float(ys[-1] - xs[-1] + R * (ny - nx))
    top = np.stack([p + xs, ys], axis=1)
    A = top[-1]
    cc = A + R * np.array([nx, ny])
    a0 = math.atan2(A[1] - cc[1], A[0] - cc[0])
    heading = np.array([math.cos(theta[-1]), math.sin(theta[-1])])
    increasing = np.array([-math.sin(a0), math.cos(a0)])
    # TRAVERSE THE ARC THE WAY THE TRANSITION ARRIVES. atan2 returns an angle in (-pi, pi], so
    # `a0 +/- m` picks the MAJOR arc (324 degrees instead of 36) and leaves a cusp worth thousands of
    # percent of curvature. The direction is chosen by matching the tangent, not by a subtraction.
    step = m if float(np.dot(increasing, heading)) > 0.0 else -m
    alphas = a0 + np.linspace(0.0, step, max(4, n // 2) + 1)
    arc = cc + R * np.stack([np.cos(alphas), np.sin(alphas)], axis=1)
    left = top[::-1][:, ::-1]
    return np.vstack([top, arc[1:], left[1:]]), p


def clothoid_corner_q(radius, smoothing, samples=96):
    """The same polyline in q-space, plus the q where it leaves the straight edges.

    q is measured from the arc centre (R, R) with the axes pointing back toward the vertex, so
    q = (R - x, R - y). The curve runs from (R - p, R) on the top edge's line to (R, R - p) on the
    left one. `edge_q = R - p` is where it leaves the straight edges and is NEGATIVE whenever
    p > R, which is why the circle's "the corner is q > 0" split cannot be reused: the flat rays
    begin at edge_q, not at 0. For the plain circular arc edge_q = 0.
    """
    points, p = clothoid_corner_cf(radius, smoothing, samples)
    q = np.stack([float(radius) - points[:, 0], float(radius) - points[:, 1]], axis=1)
    return q, float(radius) - p


def corner_sdf(qx, qy, radius, curve, edge_q):
    """Signed distance to a corner boundary given as a polyline in q-space, POSITIVE OUTSIDE.

    A piecewise boundary has no single parametric nearest point, so the nearest point is a SEGMENT
    search and the two straight edges stay as rays, beginning where the curve leaves them. The sign
    follows the curve's own inside test, which is monotone in q.y, so the reader cannot get it wrong.
    """
    best = np.full(qx.shape, np.inf)
    for i in range(len(curve) - 1):
        ax, ay = curve[i]
        bx, by = curve[i + 1]
        ex, ey = bx - ax, by - ay
        length2 = max(ex * ex + ey * ey, 1e-12)
        t = np.clip(((qx - ax) * ex + (qy - ay) * ey) / length2, 0.0, 1.0)
        px, py = ax + t * ex, ay + t * ey
        best = np.minimum(best, np.hypot(qx - px, qy - py))
    top = np.where(qx <= edge_q, np.abs(radius - qy), np.hypot(qx - edge_q, qy - radius))
    left = np.where(qy <= edge_q, np.abs(radius - qx), np.hypot(qx - radius, qy - edge_q))
    distance = np.minimum(np.minimum(best, top), left)
    order = np.argsort(curve[:, 1])
    curve_x = np.interp(qy, curve[order, 1], curve[order, 0])
    inside = np.where(qx <= edge_q, qy <= radius,
                      np.where(qy <= edge_q, qx <= radius, qx <= curve_x))
    return np.where(inside, -distance, distance)


def corners_report(radius, smoothing):
    """Measures the corner and prints key=value, so the suite can pin the numbers."""
    r = float(radius)
    curve_q, edge_q = clothoid_corner_q(r, smoothing, samples=4000)
    # back to the corner's own frame: x = R - qx, y = R - qy
    cf_x, cf_y = r - curve_q[:, 0], r - curve_q[:, 1]
    order = np.argsort(cf_y)
    ys, xs = cf_y[order], cf_x[order]
    print(f"corner_radius={r:g}")
    print(f"corner_smoothing={smoothing:g}")
    print(f"edge_offset_p={r - edge_q:.4f}")
    for y in (1.0, 5.0, 10.0):
        print(f"x_at_y_{int(y)}={float(np.interp(y, ys, xs)):.4f}")
    # x DECREASES as y grows: it starts at p on the top edge and ends at 0 on the left one.
    print(f"monotone={'yes' if np.all(np.diff(xs) <= 1e-9) else 'no'}")
    return 0


def refraction_field(h, w, corner_radius, corner_smoothing, rim_width, refraction_reach, refraction):
    """The backdrop's bend near the band's edges, and the distances every edge term shares.

    Returns `(shift_x, shift_y, to_edge, falloff_rim, falloff_refract)`.

    THE DIRECTION IS THE GRADIENT OF `to_edge`, WHICH IS THE DISTANCE TO THE NEAREST EDGE OF THE
    BAND -- the window's rounded frame AND the band's own bottom, which is the top of the content and
    is NOT a frame edge at all. Taking the direction from the frame's distance alone leaves the
    bottom edge with no gradient (it is flat there) and therefore bending nothing, which is what the
    user saw. The simulator always used the whole box and so always bent at the bottom; the two
    implementations disagreed, and this is the quantity they now name together.

    THE REACH IS ITS OWN NUMBER. Two falloffs read the same distance: the rim's (`rim_width`, the
    look of the edge) and the bend's (`refraction_reach`, how far into the band the backdrop is
    pulled). They used to be one, so the bend could not reach further without widening the rim.
    """
    yy0, xx0 = np.mgrid[0:h, 0:w].astype(float)
    co = np.array([w, h], dtype=float) * 0.5
    ppos = np.stack([xx0, yy0], axis=2)
    q = np.abs(ppos - co) - (co - corner_radius)
    if corner_smoothing > 0.001:
        curve, edge_q = clothoid_corner_q(corner_radius, corner_smoothing)
        sdf = corner_sdf(q[..., 0], q[..., 1], corner_radius, curve, edge_q)
        gy_num, gx_num = np.gradient(-sdf)
        grad_x, grad_y = -gx_num, -gy_num
    else:
        sdf = (np.sqrt((np.maximum(q, 0.0) ** 2).sum(axis=2))
               + np.minimum(np.maximum(q[..., 0], q[..., 1]), 0.0) - corner_radius)
        grad_x = np.maximum(q[..., 0], 0.0) * np.sign(ppos[..., 0] - co[0])
        grad_y = np.maximum(q[..., 1], 0.0) * np.sign(ppos[..., 1] - co[1])
    to_edge = -sdf
    falloff_rim = 1.0 - smoothstep(0.0, rim_width, to_edge)
    falloff_refract = 1.0 - smoothstep(0.0, refraction_reach, to_edge)
    largo = np.maximum(np.sqrt(grad_x ** 2 + grad_y ** 2), 1e-6)
    shift_y = (-grad_y / largo) * refraction * falloff_refract
    shift_x = (-grad_x / largo) * refraction * falloff_refract
    return shift_x, shift_y, to_edge, falloff_rim, falloff_refract


def simulate(window, backdrop, glass_alpha=GLASS_ALPHA, radius=BACKGROUND_RADIUS,
             boost=MATERIAL_BOOST, rim_strength=RIM, chrome_low=CHROME_LOW, factor=0,
             gain=MATERIAL_GAIN, refraction=REFRACTION, refraction_reach=REFRACTION_REACH,
             rim_width=RIM_WIDTH, dispersion=0.0,
             specular=SPECULAR, specular_width=SPECULAR_WIDTH, rim_colour_boost=RIM_COLOUR,
             corner_radius=CORNER_RADIUS, corner_smoothing=0.0):
    factor = min(2, max(1, factor or max(1, radius // 8)))
    # the edge geometry first, then ONE frost whose centre is bent: this is what makes the rim the
    # same material as the centre, blurred and displaced, instead of a sharp copy of the backdrop
    h0, w0 = backdrop.shape[:2]
    yy0 = np.mgrid[0:h0, 0:w0].astype(float)[0]
    shift_x, shift_y, to_edge, falloff, _falloff_refract = refraction_field(
        h0, w0, corner_radius, corner_smoothing, rim_width, refraction_reach, refraction)
    if dispersion > 0.001:
        # DISPERSION: the bend moves each wavelength a little differently, which is why Apple's
        # glass shows colour fringing at its edges and the kit carries `refraction = 70` next to
        # `dispersion = 20`. Modelled here as that ratio: the red channel is bent furthest, blue
        # least, green at the nominal. Three frosts, which is free in a simulator and NOT free in a
        # shader -- that cost is the reason this is shown before it is built.
        canales = []
        for i, escala in enumerate((1.0 + dispersion, 1.0, 1.0 - dispersion)):
            f = frost(backdrop, radius, factor, shift_y * escala, shift_x * escala)
            canales.append(f[..., i])
        desktop = np.stack(canales, axis=2)
    else:
        desktop = frost(backdrop, radius, factor, shift_y, shift_x)

    # the amplification: the backdrop's chroma around its own luminance, which a blend cannot do
    if boost > 1.001:
        l = luma(desktop)[..., None]
        desktop = np.clip(l + (desktop - l) * boost, 0, 1)

    # The tone's radius is the SHADER's, not the background radius: max(FrostRadius, bar/2).
    # Keying it to `radius` was the third of the four drifts the audit found.
    base = tone(window, max(FROST_RADIUS, h0 * 0.5))
    # the material's gain with a SOFT KNEE above 0.5, as in the shader: a hard clip turns a bright
    # backdrop into a flat white plateau, which is the "cuadro blancoso" the user reported
    boosted = desktop * gain
    over = np.maximum(boosted - 0.5, 0.0)
    desktop = np.where(boosted > 0.5, 0.5 + over / (1.0 + 2.0 * over), boosted)
    glass = (1.0 - glass_alpha) * desktop + glass_alpha * base

    # the chrome: deviation from the bar's tone, as a COVERAGE, plus chroma for the discs
    l = luma(window)
    lt = luma(base)
    darker = np.clip((lt - l) / np.maximum(lt, 1e-3), 0, 1)
    lighter = np.clip((l - lt) / np.maximum(1.0 - lt, 1e-3), 0, 1)
    by_coverage = smoothstep(chrome_low, min(1.0, chrome_low + 0.85), np.maximum(darker, lighter))
    chroma = window.max(axis=2) - window.min(axis=2)
    by_colour = smoothstep(0.15, 0.30, chroma)
    chrome = np.maximum(by_coverage, by_colour)[..., None]

    result = glass * (1 - chrome) + window * chrome

    # THE EDGE GEOMETRY IS UNCONDITIONAL, and it uses the ROUNDED distance computed above. The audit
    # found two drifts here: everything was gated on `rim_strength` (the shader applies the hairline
    # and the fillet whatever `uRim` is -- "Independent of Rim on purpose" -- and only the BAND's blend
    # is scaled by it), and the block shadowed `to_edge` with a BOX distance, which is the same defect
    # that made the corners square in the shader. `falloff`, `to_edge`, `h0` and `yy0` come from up
    # there, so the two implementations now name the same quantities.
    el = luma(desktop)[..., None]
    rim_colour = np.clip(el + (desktop - el) * max(boost, 1.2), 0, 1)
    rl = luma(rim_colour)[..., None]
    chroma = rim_colour - rl
    highest = chroma.max(axis=2)[..., None]
    lowest = chroma.min(axis=2)[..., None]
    limit = np.full_like(highest, rim_colour_boost)
    limit = np.where(highest > 0.001, np.minimum(limit, (1.0 - rl) / np.maximum(highest, 1e-6)), limit)
    limit = np.where(lowest < -0.001, np.minimum(limit, rl / np.maximum(-lowest, 1e-6)), limit)
    rim_colour = np.clip(rl + chroma * np.maximum(limit, 0.0), 0, 1)
    r = (falloff * rim_strength)[..., None]              # only the band is scaled by Rim
    result = result * (1 - r * 0.85) + rim_colour * (r * 0.85)
    # the hairline of contrast, and the fillet, both independent of Rim, as in the shader
    back = luma(desktop)[..., None]
    hair = (1.0 - smoothstep(0.0, 2.5, to_edge))[..., None]
    line_factor = np.where(back > 0.5, 0.35, 1.7)
    line = np.clip(np.clip(back + (desktop - back) * 0.5, 0, 1) * line_factor, 0, 1)
    result = result * (1 - hair * 0.35) + line * (hair * 0.35)
    # THE FILLET GOES LAST: a reflection is the outermost thing that happens to a surface
    fillet = 1.0 - smoothstep(0.0, specular_width, to_edge)
    above = np.where((h0 - 1 - yy0) < yy0, 0.55, 1.0)
    spec = (fillet * specular * above * (1.0 - 0.85 * back[..., 0]))[..., None]
    result = result * (1 - np.clip(spec, 0, 2)) + 1.0 * np.clip(spec, 0, 2)

    return np.clip(result, 0, 1)


def self_test():
    """The two cases whose answer is known by definition, plus the fringe's coverage."""
    # EVERY EDGE TERM IS EXACTLY ZERO THIS FAR IN: the band reaches 12 px, the fillet 6, the hairline
    # 2.5. Comparing the whole frame made both checks fail for a CORRECT change -- the edge terms are
    # unconditional now -- which is the difference between a test and a tripwire.
    INTERIOR = (slice(14, 46), slice(20, 180))
    rng = np.random.default_rng(7)
    backdrop = rng.random((60, 200, 3)) * 0.6
    # a synthetic title strip: a light bar with a dark glyph and a coloured disc
    window = np.full((60, 200, 3), 0.96)
    # an ANTI-ALIASED glyph: a half-covered row on top, which is the pixel whose white fringe
    # the theme bakes in and which the coverage estimate exists to soften
    window[24, 80:120] = 0.53
    window[25:35, 80:120] = 0.10
    window[20:40, 150:170] = np.array([0.95, 0.35, 0.35])

    # boost 1.0 here: with alpha 0 the band is the frosted backdrop and NOTHING else, and the
    # amplification is a separate step that the comparison would otherwise include
    plana = np.full((60, 200, 3), 0.96)          # a bar with no chrome at all
    sin_tono = simulate(plana, backdrop, glass_alpha=0.0, rim_strength=0.0, boost=1.0, gain=1.0,
                        refraction=0.0)
    esperado = frost(backdrop, BACKGROUND_RADIUS, max(1, BACKGROUND_RADIUS // 8))
    e1 = np.abs(sin_tono[INTERIOR] - esperado[INTERIOR]).max()
    print(f"  GlassAlpha 0 -> the frosted backdrop            (max diff {e1:.4f})")

    sin_mezcla = simulate(window, backdrop, glass_alpha=1.0, rim_strength=0.0, boost=1.0, gain=1.0)
    base = tone(window, max(FROST_RADIUS, window.shape[0] * 0.5))
    fundido = np.zeros_like(base)
    l = luma(window); lt = luma(base)
    d = np.clip((lt - l) / np.maximum(lt, 1e-3), 0, 1)
    li = np.clip((l - lt) / np.maximum(1.0 - lt, 1e-3), 0, 1)
    cov = smoothstep(CHROME_LOW, min(1.0, CHROME_LOW + 0.85), np.maximum(d, li))[..., None]
    chr_ = smoothstep(0.15, 0.30, window.max(axis=2) - window.min(axis=2))[..., None]
    ch = np.maximum(cov, chr_)
    # THE MIDDLE ROWS ONLY. The hairline and the fillet are applied unconditionally now, as in the
    # shader, so the edge rows deliberately differ from a formula that describes the material alone --
    # they are asserted by their own tests. Comparing the whole frame made this check fail for a
    # correct change, which is the difference between a test and a tripwire.
    e2 = np.abs(sin_mezcla[INTERIOR] - (base * (1 - ch) + window * ch)[INTERIOR]).max()
    print(f"  GlassAlpha 1 -> the bar's own tone              (max diff {e2:.4f})")

    # the glyph's EDGE must be PARTIAL, which is what removes the baked-in white fringe, and
    # the first version of this check probed a row of solid glyph where 1.0 is CORRECT -- the
    # test was wrong, not the model
    borde = ch[24, 100, 0]
    centro = ch[30, 100, 0]
    print(f"  glyph edge coverage {borde:.2f} (must be partial), centre {centro:.2f} (must be 1)")

    ok = e1 < 1e-6 and abs(e2) < 1e-6 and 0.2 < borde < 0.95 and centro > 0.95
    print("  SELF-TEST", "OK" if ok else "FAILED")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--window", help="the title strip with the effect OFF")
    ap.add_argument("--backdrop", help="the same region of the desktop, window out of the way")
    ap.add_argument("--out", default="/tmp/banda-simulada.png")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--corners", action="store_true",
                    help="mide la esquina (abultamiento squircle) y sale en clave=valor")
    ap.add_argument("--GlassAlpha", type=float, default=GLASS_ALPHA)
    ap.add_argument("--BackgroundRadius", type=int, default=BACKGROUND_RADIUS)
    ap.add_argument("--MaterialBoost", type=float, default=MATERIAL_BOOST)
    ap.add_argument("--MaterialGain", type=float, default=MATERIAL_GAIN)
    ap.add_argument("--Refraction", type=float, default=REFRACTION)
    ap.add_argument("--RefractionReach", type=float, default=REFRACTION_REACH,
                    help="how far the bend reaches inward, in px (separate from RimWidth)")
    ap.add_argument("--RimWidth", type=float, default=RIM_WIDTH)
    ap.add_argument("--CornerRadius", type=float, default=CORNER_RADIUS)
    ap.add_argument("--CornerSmoothing", type=float, default=0.0,
                    help="el cornerSmoothing del kit (0 = arco circular, 0.6 = el valor medido)")
    ap.add_argument("--RimColour", type=float, default=RIM_COLOUR)
    ap.add_argument("--Specular", type=float, default=SPECULAR)
    ap.add_argument("--SpecularWidth", type=float, default=SPECULAR_WIDTH)
    ap.add_argument("--Dispersion", type=float, default=0.0,
                    help="fraction of the bend that separates per channel; the kit says 20/70")
    ap.add_argument("--Rim", type=float, default=RIM)
    ap.add_argument("--ChromeLow", type=float, default=CHROME_LOW)
    ap.add_argument("--FrostDownsample", type=int, default=0)
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if args.corners:
        return corners_report(args.CornerRadius, args.CornerSmoothing)
    if not args.window or not args.backdrop:
        ap.error("--window and --backdrop are required (or use --self-test)")
    import os
    for ruta in (args.window, args.backdrop):
        if not os.path.exists(ruta):
            print(f"missing capture: {ruta}")
            print()
            print("The two captures are what this reads, and ./capture-pair.sh takes them both in")
            print("one command: it reads the band's rectangle from the effect's own journal, takes")
            print("the screen with the effect unloaded, waits while you move the window away, takes")
            print("it again, crops both to the same strip and reloads the effect.")
            print()
            print("  ./capture-pair.sh")
            print("  python3 simulate.py --window /tmp/titulo.png --backdrop /tmp/fondo.png")
            return 2
    w = np.asarray(Image.open(args.window).convert("RGB"), dtype=float) / 255.0
    b = np.asarray(Image.open(args.backdrop).convert("RGB"), dtype=float) / 255.0
    if w.shape != b.shape:
        print(f"the two crops must be the same size: window {w.shape}, backdrop {b.shape}")
        return 2
    out = simulate(w, b, args.GlassAlpha, args.BackgroundRadius, args.MaterialBoost,
                   args.Rim, args.ChromeLow, args.FrostDownsample, args.MaterialGain,
                   args.Refraction, args.RefractionReach, args.RimWidth, args.Dispersion, args.Specular,
                   args.SpecularWidth, args.RimColour, args.CornerRadius,
                   args.CornerSmoothing)
    Image.fromarray((out * 255).astype(np.uint8)).save(args.out)
    print(f"simulated band -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

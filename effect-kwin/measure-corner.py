#!/usr/bin/env python3
"""Measures the SHAPE of a window corner from pixels, instead of trusting a formula.

WHY THIS EXISTS. M2 was built once the wrong way (HANDOFF.md section 10c). The two numbers it
pinned -- a 4.6229 px bulge and a 0.04 deg gradient -- were both measured honestly and both were
true, about a curve of the wrong FAMILY: a superellipse centred on the corner vertex where Apple
uses an arc plus two tangent transitions. The user's eye found it in one look, after a session of
arithmetic. When the thing being judged is a SHAPE, the test that matters compares the shape, not
two numbers extracted from it.

So this reads the boundary out of a coverage image -- a synthetic corner whose answer is known
FIRST, a screenshot later -- and reports the boundary itself, row by row, next to the closed form.

THE THREE WAYS THE FIRST ATTEMPT DIED, and what guards each:

  1. FRAME OF REFERENCE. The frame is DERIVED (the window's bounding box) and then CHECKED: below
     the corner the left edge must be straight, and to the right of it the top edge must be. A
     profile that would be measured in the wrong frame is REFUSED, not printed.
  2. A MALFORMED KNOWN-VALUE CASE. The synthetic image is rasterised from the IMPLICIT geometry of
     the shape; the expected profile comes from the explicit closed form. The two are different
     paths to the same curve, so the case cannot be "known" by copying the measurement -- and an
     all-background image must be refused instead of measured.
  3. A NAIVE ROW SCAN cannot describe a FLAT corner: it reports the same x for every row and
     cannot tell a flat corner from a broken frame. Here the profile AND the missing area are
     reported, so a boundary that never leaves the far edge (the wrong superellipse of 10c) and
     one that never leaves the near edge (a square) are different measurements, not silence.

USAGE

    python3 measure-corner.py --self-test
    python3 measure-corner.py --image shot.png --corner tl --radius 20

The corner's own frame: the origin is the window's outer corner vertex, x grows along the top
edge and y grows DOWN along the side edge. `inset(y)` is where the boundary is on row y, measured
from the side edge: 0 is the straight edge, r is the far edge of the r x r corner box.
"""
import argparse
import math
import os
import sys
import tempfile

import numpy as np
from PIL import Image


# --------------------------------------------------------------------------------------------
# The shapes, as IMPLICIT geometry. These draw the synthetic corners. `inside` is the window.
# --------------------------------------------------------------------------------------------
def inside_circle(px, py, r):
    """The rounded box's arc: a circle of radius r centred at (r, r) in the corner frame."""
    return (px - r) ** 2 + (py - r) ** 2 <= r * r


def inside_flat(px, py, r):
    """A square corner: the window fills its whole corner box."""
    return np.ones_like(px, dtype=bool)


def inside_superellipse(px, py, r, smoothing):
    """The family the tree carried until 10c: (x/r)^n + (y/r)^n >= 1, n = 2 + 5*smoothing.

    At n=2 that is a circle centred on the VERTEX, not the rounded box's arc centred on (r, r).
    That frame difference is the defect 10c names, and it is here to be DESCRIBED, not trusted.
    """
    n = 2.0 + 5.0 * max(0.0, smoothing)
    xa = np.power(np.maximum(px, 0.0) / r, n)
    ya = np.power(np.maximum(py, 0.0) / r, n)
    return xa + ya >= 1.0


# --------------------------------------------------------------------------------------------
# The same shapes, as EXPLICIT closed forms. These are the "known answers" of the self-test.
# --------------------------------------------------------------------------------------------
def inset_circle(y, r):
    """x of the (r, r)-centred arc at height y: r - sqrt(r^2 - (r-y)^2)."""
    y = np.asarray(y, dtype=float)
    u = np.clip(r - y, 0.0, r)
    return r - np.sqrt(np.maximum(r * r - u * u, 0.0))


def inset_flat(y, r):
    return np.zeros_like(np.asarray(y, dtype=float))


def inset_superellipse(y, r, smoothing):
    """x(y) of (x/r)^n + (y/r)^n = 1 with n = 2 + 5*smoothing: r * (1 - (y/r)^(2/p))^(p/2)."""
    y = np.asarray(y, dtype=float)
    n = 2.0 + 5.0 * max(0.0, smoothing)
    u = np.clip(y / r, 0.0, 1.0)
    return r * np.power(np.maximum(1.0 - np.power(u, n), 0.0), 1.0 / n)


def diagonal_circle(r):
    """Distance from the vertex to where the (r, r)-centred arc crosses the diagonal."""
    return r * (math.sqrt(2.0) - 1.0)


def diagonal_superellipse(r, smoothing):
    """Distance from the vertex to where (x/r)^n + (y/r)^n = 1 crosses the diagonal."""
    n = 2.0 + 5.0 * max(0.0, smoothing)
    t = r * math.pow(2.0, -1.0 / n)
    return t * math.sqrt(2.0)


# --------------------------------------------------------------------------------------------
# THE CONSTRUCTION THE KIT'S `cornerSmoothing` ACTUALLY NAMES: Figma's squircle.
#
# Section 10c described Apple's construction as "an arc shrunk to r*(1-s) plus two tangent Bezier
# transitions that reach the straight edge at r*s from the vertex". Measured against the canonical
# algorithm, none of those three numbers is right -- and the "Apple's construction" column of that
# section's table (16.12 / 12.55 / 13.25) is non-monotonic and reproduced by neither this curve nor
# any other. What the algorithm does, from Figma's "Desperately seeking squircles" as implemented
# by MartinRGB and the `figma_squircle` crate:
#
#   p          = (1 + s) * R     the straight edges end p from the vertex, NOT R and NOT s*R
#   arc        = radius R, its MEASURE shrunk to 90*(1-s) degrees, centred at (R, R)
#   transition = two cubic Beziers, tangent to the edge at p and to the arc
#
# At s=0 it collapses exactly to the circular corner (p=R, measure 90, zero-length transitions).
# --------------------------------------------------------------------------------------------
def figma_params(radius, smoothing):
    R, s = float(radius), float(smoothing)
    p = (1.0 + s) * R
    arc_measure = 90.0 * (1.0 - s)
    chord = math.sin(math.radians(arc_measure / 2.0)) * R * math.sqrt(2.0)
    alpha = (90.0 - arc_measure) / 2.0
    p3p4 = R * math.tan(math.radians(alpha / 2.0))
    beta = 45.0 * s
    c = p3p4 * math.cos(math.radians(beta))
    d = c * math.tan(math.radians(beta))
    b = (p - chord - c - d) / 3.0
    return {"p": p, "chord": chord, "a": 2.0 * b, "b": b, "c": c, "d": d}


def _bezier(p0, c1, c2, p3, t):
    u = 1.0 - t
    return (u ** 3 * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t ** 3 * p3[1])


def figma_curve(radius, smoothing, samples=180):
    """The top-left corner as a polyline, from (0, p) on the left edge to (p, 0) on the top."""
    q = figma_params(radius, smoothing)
    p, chord, a, b, c, d = q["p"], q["chord"], q["a"], q["b"], q["c"], q["d"]
    R = float(radius)
    start, p1 = (0.0, p), (d, p - (a + b + c))
    p2 = (p1[0] + chord, p1[1] - chord)          # the arc's endpoints, radius R centred at (R, R)
    c1, c2 = (0.0, p - a), (0.0, p - (a + b))
    c3, c4 = (p2[0] + c, p2[1] - d), (p2[0] + b + c, p2[1] - d)
    points = []
    for i in range(samples + 1):
        t = i / samples
        if t < 1.0 / 3.0:
            points.append(_bezier(start, c1, c2, p1, t * 3.0))
        elif t < 2.0 / 3.0:
            ang1 = math.atan2(p1[1] - R, p1[0] - R)
            ang2 = math.atan2(p2[1] - R, p2[0] - R)
            while ang2 - ang1 > math.pi:
                ang2 -= 2.0 * math.pi
            while ang1 - ang2 > math.pi:
                ang2 += 2.0 * math.pi
            ang = ang1 + (ang2 - ang1) * ((t - 1.0 / 3.0) * 3.0)
            points.append((R + R * math.cos(ang), R + R * math.sin(ang)))
        else:
            points.append(_bezier(p2, c3, c4, (p, 0.0), (t - 2.0 / 3.0) * 3.0))
    return points


def inset_figma(y, radius, smoothing):
    """x(y) of the Figma corner in the corner's own frame: the curve, then the straight edge."""
    y = np.asarray(y, dtype=float)
    points = np.array(figma_curve(radius, smoothing))
    order = np.argsort(points[:, 1])
    ys, xs = points[order, 1], points[order, 0]
    return np.interp(y, ys, xs)


# --------------------------------------------------------------------------------------------
# THE CURVATURE INSTRUMENT (M2.5). The shape instrument above judges where the boundary IS; this
# one judges HOW IT TURNS. A circular arc has constant curvature 1/R by definition, Apple's
# continuous corner spreads that curvature without ever exceeding it, and the Figma construction
# on screen today OVERSHOOTS: its kappa reaches 0.0735 where the arc is 0.05 (+47%), which is the
# "angle" the user sees in the highlight. Overshoot is the measurable form of "not G2", so that is
# what the verdict tests.
#
# The curvature is computed from an ordered polyline, with the derivatives taken against ARC LENGTH
# (not the sample index, which is not uniform on a piecewise curve) and a moving average to keep
# the segment/pixel noise from inventing maxima. `radius` is the reference: the arc's own 1/R.
# --------------------------------------------------------------------------------------------
def circle_arc_points(radius, samples=2000):
    """The corner's circular arc, centred at (R, R), from (0, R) to (R, 0). Curvature = 1/R."""
    r = float(radius)
    phi = np.linspace(0.0, math.pi / 2.0, int(samples) + 1)
    return np.stack([r - r * np.cos(phi), r - r * np.sin(phi)], axis=1)


def curvature_along(points, smooth=9):
    """kappa(s) along an ordered polyline, in 1/px, as TURNING PER ARC LENGTH.

    Two estimators died before this one, and both were mine:
      * the second derivative of x and y against arc length reads a SPIKE at every seam where the
        sampling density changes (the transition and the arc are sampled differently), which on the
        clothoid invented a +10% bump exactly at the two joins;
      * pre-smoothing the POINTS rounds those seams and invents a bump of its own (measured +14% on
        a clothoid whose signed turning is provably <= 1/R everywhere).
    The turning angle between consecutive segments over their mean length is the same quantity, is
    immune to the sampling, and is smoothed only AFTERWARDS -- the geometry is never touched.
    """
    P = np.asarray(points, dtype=float)
    if P.shape[0] < 4:
        return np.zeros(P.shape[0])
    seg = np.diff(P, axis=0)
    length = np.hypot(seg[:, 0], seg[:, 1])
    if float(length.max()) <= 1e-12:
        return np.zeros(P.shape[0])
    angle = np.unwrap(np.arctan2(seg[:, 1], seg[:, 0]))
    turning = np.abs(np.diff(angle))
    mean_len = 0.5 * (length[:-1] + length[1:])
    kappa = turning / np.maximum(mean_len, 1e-12)
    kappa = np.concatenate([[kappa[0]], kappa, [kappa[-1]]])
    k = int(smooth) | 1                     # odd
    if k > 1 and kappa.size > k:
        pad = k // 2
        padded = np.concatenate([np.repeat(kappa[:1], pad), kappa, np.repeat(kappa[-1:], pad)])
        kappa = np.convolve(padded, np.ones(k) / k, mode="valid")
    return kappa


def curvature_verdict(points, radius, tolerance=0.01, smooth=9):
    """Judge a boundary's curvature against the arc's own 1/R.

    `spike` is the verdict: TRUE when the curvature somewhere EXCEEDS the arc's by more than
    `tolerance` (1% by default). That is what makes a corner read as an angle, and it is what the
    current Figma curve does by +47%. `maxima` counts interior local maxima ABOVE the arc, so a
    profile that oscillates instead of turning once is visible too.
    """
    k = curvature_along(points, smooth)
    arc = 1.0 / float(radius)
    kmax, kmin = float(k.max()), float(k.min())
    # A maximum only counts when it is ABOVE the arc: on a constant-curvature arc every sample is a
    # local maximum by `>=` and floating point supplies hundreds of them (measured: 570 on a circle),
    # which is a metric flattering itself rather than a finding.
    maxima = 0
    if k.size >= 3:
        above = k > arc * (1.0 + tolerance)
        maxima = int(np.sum(above[1:-1] & (k[1:-1] >= k[:-2]) & (k[1:-1] >= k[2:])))
    return {"curvature_min": kmin, "curvature_max": kmax, "arc_curvature": arc,
            "overshoot_pct": (kmax / arc - 1.0) * 100.0,
            "spike": kmax > arc * (1.0 + tolerance), "maxima": maxima}


# --------------------------------------------------------------------------------------------
# THE CANDIDATES for a curvature-continuous corner. Each returns an ordered polyline in the corner's
# own frame from (0, p) on the left edge to (p, 0) on the top, so they can be measured with the same
# instrument and, later, dropped into the same nearest-point search.
# --------------------------------------------------------------------------------------------
def superellipse_arc_points(radius, exponent, samples=2000):
    """A superellipse CENTRED AT THE ARC CENTRE (R, R): |x-R|^n + |y-R|^n = R^n.

    At n=2 this IS the circular arc, so the family generalises the approved shape instead of
    replacing it. THIS IS NOT THE FAMILY 10c THREW AWAY: that one was centred on the corner VERTEX,
    `c(phi) = r*(sin^p, cos^p)` with the invented `n = 2 + 5*s`, and it produced a nearly square
    corner (at y=5 its boundary was at x=20 where the circle's was at 6.8). Here the vertex is not
    the centre of anything.
    """
    r, n = float(radius), float(exponent)
    q = 2.0 / n
    phi = np.linspace(0.0, math.pi / 2.0, int(samples) + 1)
    x = r - r * np.power(np.cos(phi), q)
    y = r - r * np.power(np.sin(phi), q)
    return np.stack([x, y], axis=1)


def g2_bezier_corner_points(radius, arc_measure_deg, edge_offset, samples=2000):
    """Apple-style corner: a circular arc of `arc_measure_deg` plus two cubic Beziers whose curvature
    MATCHES the arc (1/R) at one end and the straight edge (0) at the other, so both junctions are
    G2 instead of the Figma construction's G1.

    The construction, for the top transition. Let A be the arc's top endpoint, `tA` its tangent
    (pointing from the edge into the arc), E=(p,0) the point on the straight edge.
        C2 = A - b*tA, with b chosen so C2 lies ON the edge line  ->  kappa(E) = 0
        C1 = (E - a*(1,0)), with a chosen so kappa(A) = 1/R
    Both tangents are matched by construction, so the only thing left to MEASURE is whether the
    curvature between them stays at or below 1/R -- which is exactly what the instrument does.
    """
    R, p = float(radius), float(edge_offset)
    m = math.radians(float(arc_measure_deg))
    cc = np.array([R, R])
    alpha_top = 5.0 * math.pi / 4.0 + m / 2.0
    alpha_left = 5.0 * math.pi / 4.0 - m / 2.0
    A = cc + R * np.array([math.cos(alpha_top), math.sin(alpha_top)])
    # tangent along the arc travelling from the top endpoint towards the left one (decreasing alpha)
    tA = np.array([math.sin(alpha_top), -math.cos(alpha_top)])
    if abs(tA[1]) < 1e-9:
        tA[1] = 1e-9
    b = A[1] / tA[1]
    C2 = A - b * tA                              # on y = 0, which is what makes kappa(E) = 0
    d = 1.5 * float(np.linalg.norm(A - C2)) ** 3 / (R * A[1])
    # two solutions for C1's x; keep the one BETWEEN the edge point and C2, or the control polygon
    # doubles back and the Bezier wiggles instead of turning once.
    candidates = [C2[0] + d, C2[0] - d]
    inside = [cx for cx in candidates if min(C2[0], p) < cx < max(C2[0], p)]
    C1x = inside[0] if inside else min(candidates, key=lambda cx: abs(cx - 0.5 * (C2[0] + p)))
    E = np.array([p, 0.0])
    C1 = np.array([C1x, 0.0])
    n1 = max(2, int(samples) // 2)
    top = np.array([_bezier(E, C1, C2, A, i / n1) for i in range(n1 + 1)])
    # the arc, sampled from alpha_top down to alpha_left
    n2 = max(2, int(samples) // 2)
    alphas = np.linspace(alpha_top, alpha_left, n2 + 1)
    arc = cc + R * np.stack([np.cos(alphas), np.sin(alphas)], axis=1)
    # the left transition is the mirror of the top one (the corner is symmetric about x = y), so it
    # runs from A_left back out to (0, p).
    left = top[::-1][:, ::-1]
    return np.vstack([top, arc[1:], left[1:]])


def clothoid_corner_points(radius, arc_measure_deg, samples=4000):
    """A true G2 corner: an Euler-spiral (clothoid) transition whose curvature rises LINEARLY from 0
    at the straight edge to 1/R at the arc, then the circular arc for the middle.

    kappa(s) = s/(R*L) is monotone by construction, so it can never overshoot -- which is exactly
    what the instrument measures. The clothoid is the standard transition curve in road and rail
    design and is used in type design for G2 corners; here it is the candidate that the two
    algebraic families above fail to be.

    The transition's turn is fixed by the arc's measure (`dtheta = (90 - m)/2`), which fixes its
    length, and the corner's symmetry about x = y then fixes where it meets the straight edge.
    """
    R = float(radius)
    m = math.radians(float(arc_measure_deg))
    dtheta = (math.pi / 2.0 - m) / 2.0
    L = 2.0 * R * dtheta
    n = max(8, int(samples) // 2)
    s = np.linspace(0.0, L, n + 1)
    theta = math.pi - (s * s) / (2.0 * R * L)     # heading: starts at 180 deg (-x), turns toward +y
    ds = L / n
    xs = np.zeros(n + 1)
    ys = np.zeros(n + 1)
    for i in range(1, n + 1):
        xs[i] = xs[i - 1] + ds * 0.5 * (math.cos(theta[i - 1]) + math.cos(theta[i]))
        ys[i] = ys[i - 1] + ds * 0.5 * (math.sin(theta[i - 1]) + math.sin(theta[i]))
    # the arc's centre must sit on the diagonal for the corner to be symmetric, and that fixes the
    # edge offset p. The normal towards the centre is perpendicular to the end heading.
    nx, ny = math.cos(theta[-1] + math.pi / 2.0), math.sin(theta[-1] + math.pi / 2.0)
    if nx + ny < 0.0:
        nx, ny = -nx, -ny
    p = float(ys[-1] - xs[-1] + R * (ny - nx))
    top = np.stack([p + xs, ys], axis=1)
    A = top[-1]
    cc = A + R * np.array([nx, ny])
    # TRAVERSE THE ARC THE WAY THE TRANSITION ARRIVES. `atan2` returns an angle in (-pi, pi], so
    # `a0 +/- m` picked the MAJOR arc (324 degrees instead of 36) and left a cusp worth +5408% of
    # curvature. The direction is chosen by matching the tangent, not by the sign of a subtraction.
    a0 = math.atan2(A[1] - cc[1], A[0] - cc[0])
    heading = np.array([math.cos(theta[-1]), math.sin(theta[-1])])
    increasing = np.array([-math.sin(a0), math.cos(a0)])
    step = m if float(np.dot(increasing, heading)) > 0.0 else -m
    alphas = a0 + np.linspace(0.0, step, max(4, n // 2) + 1)
    arc = cc + R * np.stack([np.cos(alphas), np.sin(alphas)], axis=1)
    left = top[::-1][:, ::-1]
    return np.vstack([top, arc[1:], left[1:]])


def render_inset(inset_fn, extent, pad=6, ss=8):
    """Coverage of a corner given its boundary as x(y) = inset_fn(y), over a [0, extent] box.

    The composite corner runs to p = (1+s)*R, further than R, so the corner box has to be given
    explicitly: the box used for the single-circle cases stops at R and would call the transition
    region "outside the corner" and fill it with the straight edge.
    """
    n = int(round(extent)) + 1 + pad
    sub = (np.arange(ss) + 0.5) / ss - 0.5
    rows = (np.arange(n)[:, None] + sub[None, :]).ravel()
    cols = (np.arange(n)[:, None] + sub[None, :]).ravel()
    grid_x, grid_y = np.meshgrid(cols, rows)
    inside = grid_x >= inset_fn(grid_y)
    return inside.reshape(n, ss, n, ss).mean(axis=(1, 3))


# --------------------------------------------------------------------------------------------
# Rendering a synthetic corner, and reading a corner out of coverage.
# --------------------------------------------------------------------------------------------
def render_corner(shape_test, r, pad=6, ss=8):
    """Coverage [0,1] of a top-left corner, supersampled by `ss`.

    The vertex is at pixel (0, 0) and the window fills toward +x/+y. `shape_test(px, py, r)` says
    whether a point is inside the corner box; outside the box the window is the straight edges.
    """
    n = int(round(r)) + 1 + pad
    # PIXEL CENTRES, because the reader measures centres: pixel p covers [p - 0.5, p + 0.5), so a
    # sharp edge at continuous x = e gives coverage(p) = clamp(p + 0.5 - e, 0, 1) and the 0.5
    # crossing lands on e. Sampling pixel CORNERS instead put a systematic half-pixel shift between
    # the render and the reader -- measured, not guessed: the circle read 5.64 where its arc is at
    # 6.77 for y=5.
    sub = (np.arange(ss) + 0.5) / ss - 0.5
    rows = (np.arange(n)[:, None] + sub[None, :]).ravel()
    cols = (np.arange(n)[:, None] + sub[None, :]).ravel()
    py = rows[:, None]
    px = cols[None, :]
    # Both in the full (row, col) shape: a mask built from a (n,1) and a (1,n) array cannot index
    # the (1,n) one, which is how the first run of this file died.
    grid_x, grid_y = np.broadcast_arrays(px, py)
    inside = ((grid_y > r) | (grid_x > r)).copy()
    box = (grid_x <= r) & (grid_y <= r)
    inside[box] = shape_test(grid_x[box], grid_y[box], r)
    return inside.reshape(n, ss, n, ss).mean(axis=(1, 3))


def _first_crossing(line):
    """Subpixel index where a 1-D coverage line crosses 0.5, searched from its start.

    A line that is already inside at index 0 has its boundary at or left of the frame, which is
    the honest answer 0.0 for a straight edge -- not an interpolation against a phantom pixel.
    """
    inside = line >= 0.5
    j = int(np.argmax(inside))
    if not inside[j]:
        raise FrameError("no window pixel along this line")
    if j == 0:
        return 0.0
    c0, c1 = float(line[j - 1]), float(line[j])
    if c1 <= c0:
        return float(j)
    return float(j - 1 + (0.5 - c0) / (c1 - c0))


def _bilinear(img, ys, xs):
    ys = np.clip(ys, 0, img.shape[0] - 1)
    xs = np.clip(xs, 0, img.shape[1] - 1)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    y1 = np.minimum(y0 + 1, img.shape[0] - 1)
    x1 = np.minimum(x0 + 1, img.shape[1] - 1)
    fy = ys - y0
    fx = xs - x0
    return (img[y0, x0] * (1 - fy) * (1 - fx) + img[y1, x0] * fy * (1 - fx)
            + img[y0, x1] * (1 - fy) * fx + img[y1, x1] * fy * fx)


class FrameError(Exception):
    """The image cannot support the measurement: the straight edges are not where they must be."""


def measure_corner(coverage, radius, corner="tl"):
    """Describe the corner. Raises FrameError rather than reporting a profile in a wrong frame."""
    arr = coverage
    if corner in ("tr", "br"):
        arr = arr[:, ::-1]
    if corner in ("bl", "br"):
        arr = arr[::-1, :]

    foreground = arr >= 0.5
    if not foreground.any():
        raise FrameError("empty image: no window pixels at all")
    row_hits = np.where(foreground.any(axis=1))[0]
    col_hits = np.where(foreground.any(axis=0))[0]
    y0, x0 = int(row_hits[0]), int(col_hits[0])

    # THE FRAME IS CHECKED, NOT ASSUMED. Below the corner the left edge must be straight at x0;
    # right of the corner the top edge must be straight at y0. If they are not, this is not the
    # corner the caller thinks it is, and a profile from it would be a measurement of nothing.
    check_y = y0 + radius + 2
    if check_y < arr.shape[0]:
        left = _first_crossing(arr[check_y])
        if abs(left - x0) > 1.5:
            raise FrameError(f"left edge is not straight below the corner: x={left:.2f} at y={check_y}, expected {x0}")
    check_x = x0 + radius + 2
    if check_x < arr.shape[1]:
        top = _first_crossing(arr[:, check_x])
        if abs(top - y0) > 1.5:
            raise FrameError(f"top edge is not straight right of the corner: y={top:.2f} at x={check_x}, expected {y0}")

    profile = []
    for k in range(radius + 1):
        yy = y0 + k
        if yy >= arr.shape[0]:
            break
        profile.append(max(0.0, _first_crossing(arr[yy]) - x0))

    # THE FLAT RUN: how many rows from the top keep the boundary at the corner box's far edge.
    # This is the measurement the naive row scan could not make; a flat corner is not an error.
    flat_threshold = radius - 0.5
    flat_run = 0
    for value in profile:
        if value >= flat_threshold:
            flat_run += 1
        else:
            break

    missing_area = float(np.sum(profile[:radius]))
    diag = _diagonal_distance(arr, x0, y0, radius)
    return {
        "vertex": (x0, y0),
        "profile": profile,
        "missing_area": missing_area,
        "flat_run": flat_run,
        "diagonal_distance": diag,
        "diagonal_minus_radius": diag - radius,
        "x_at_y": {k: profile[k] for k in (1, 5, 10) if k < len(profile)},
    }


def _diagonal_distance(coverage, x0, y0, radius):
    """Distance from the vertex to the boundary along the 45 degree line, subpixel."""
    t = np.linspace(0.0, radius * math.sqrt(2.0) + 3.0, 4000)
    step = t / math.sqrt(2.0)
    vals = _bilinear(coverage, y0 + step, x0 + step)
    inside = vals >= 0.5
    j = int(np.argmax(inside))
    if not inside[j]:
        raise FrameError("the diagonal never enters the window")
    if j == 0:
        return 0.0
    c0, c1 = float(vals[j - 1]), float(vals[j])
    frac = 0.5 if c1 <= c0 else (0.5 - c0) / (c1 - c0)
    return float(t[j - 1] + frac * (t[j] - t[j - 1]))


# --------------------------------------------------------------------------------------------
# The self-test: the known-value cases, each one a failure mode of the first attempt.
# --------------------------------------------------------------------------------------------
RADIUS = 20.0
SUPERELLIPSE_SMOOTHING = 0.6   # the kit's cornerSmoothing, the curve 10c replaced
RENDER_SS = 8


def _fmt(value, digits=2):
    return f"{value:.{digits}f}"


def _case_circle():
    coverage = render_corner(inside_circle, RADIUS, ss=RENDER_SS)
    measured = measure_corner(coverage, int(RADIUS))
    expected_area = float(np.sum(inset_circle(np.arange(int(RADIUS)), RADIUS)))
    errors = [abs(measured["profile"][k] - float(inset_circle(k, RADIUS))) for k in (1, 5, 10)]
    expected_diag = diagonal_circle(RADIUS) - RADIUS
    problems = []
    if max(errors) > 0.2:
        problems.append(f"profile error {max(errors):.3f} > 0.2")
    if abs(measured["missing_area"] - expected_area) > 2.0:
        problems.append(f"missing area {measured['missing_area']:.2f} vs {expected_area:.2f}")
    if abs(measured["diagonal_minus_radius"] - expected_diag) > 0.4:
        problems.append(f"diagonal {measured['diagonal_minus_radius']:.2f} vs {expected_diag:.2f}")
    fields = (f"sweep_err_max={_fmt(max(errors), 3)} missing_area={_fmt(measured['missing_area'])}"
              f" expected_missing_area={_fmt(expected_area)}"
              f" x_at_y_1={_fmt(measured['x_at_y'][1])} x_at_y_5={_fmt(measured['x_at_y'][5])}"
              f" x_at_y_10={_fmt(measured['x_at_y'][10])}"
              f" diagonal_minus_r={_fmt(measured['diagonal_minus_radius'])} flat_run={measured['flat_run']}")
    return problems, fields


def _case_flat():
    coverage = render_corner(inside_flat, RADIUS, ss=RENDER_SS)
    measured = measure_corner(coverage, int(RADIUS))
    problems = []
    worst = max(measured["profile"]) if measured["profile"] else 0.0
    if worst > 0.2:
        problems.append(f"a flat corner measured inset {worst:.2f}")
    if measured["missing_area"] > 0.5:
        problems.append(f"a flat corner measured missing area {measured['missing_area']:.2f}")
    fields = (f"profile_max={_fmt(worst)} missing_area={_fmt(measured['missing_area'])}"
              f" diagonal_minus_r={_fmt(measured['diagonal_minus_radius'])} flat_run={measured['flat_run']}")
    return problems, fields


def _case_spike():
    coverage = render_corner(
        lambda px, py, r: inside_superellipse(px, py, r, SUPERELLIPSE_SMOOTHING),
        RADIUS, ss=RENDER_SS)
    measured = measure_corner(coverage, int(RADIUS))
    expected_area = float(np.sum(
        inset_superellipse(np.arange(int(RADIUS)), RADIUS, SUPERELLIPSE_SMOOTHING)))
    expected_diag = diagonal_superellipse(RADIUS, SUPERELLIPSE_SMOOTHING) - RADIUS
    errors = [abs(measured["profile"][k]
                  - float(inset_superellipse(k, RADIUS, SUPERELLIPSE_SMOOTHING))) for k in (1, 5, 10)]
    problems = []
    if max(errors) > 0.2:
        problems.append(f"profile error {max(errors):.3f} > 0.2")
    if abs(measured["missing_area"] - expected_area) > 3.0:
        problems.append(f"missing area {measured['missing_area']:.2f} vs {expected_area:.2f}")
    if abs(measured["diagonal_minus_radius"] - expected_diag) > 0.4:
        problems.append(f"diagonal {measured['diagonal_minus_radius']:.2f} vs {expected_diag:.2f}")
    # And the point of the case: this curve must be DESCRIBED as the flat, near-square corner the
    # user saw, not refused and not silently rounded.
    if measured["flat_run"] < 10:
        problems.append(f"the flat run reads {measured['flat_run']} rows, expected > 10")
    fields = (f"sweep_err_max={_fmt(max(errors), 3)} missing_area={_fmt(measured['missing_area'])}"
              f" expected_missing_area={_fmt(expected_area)}"
              f" x_at_y_1={_fmt(measured['x_at_y'][1])} x_at_y_5={_fmt(measured['x_at_y'][5])}"
              f" x_at_y_10={_fmt(measured['x_at_y'][10])}"
              f" diagonal_minus_r={_fmt(measured['diagonal_minus_radius'])} flat_run={measured['flat_run']}")
    return problems, fields


def _case_apple():
    """The construction the kit's cornerSmoothing names, measured from pixels.

    It is the case 10c got wrong BOTH in prose and in a table: the arc keeps radius R and only its
    measure shrinks, the straight edges end at p=(1+s)*R, and the middle of the corner is EXACTLY
    the circle. The case pins those three facts by measurement, so a future rewrite cannot quietly
    become a superellipse again.
    """
    smoothing = SUPERELLIPSE_SMOOTHING
    params = figma_params(RADIUS, smoothing)
    extent = int(round(params["p"]))
    coverage = render_inset(lambda y: inset_figma(y, RADIUS, smoothing), extent, ss=RENDER_SS)
    measured = measure_corner(coverage, extent)
    expected = {k: float(inset_figma(k, RADIUS, smoothing)) for k in (1, 5, 10)}
    errors = [abs(measured["profile"][k] - expected[k]) for k in expected]
    profile = measured["profile"]
    problems = []
    if max(errors) > 0.2:
        problems.append(f"profile error {max(errors):.3f} > 0.2")
    if any(profile[i] < profile[i + 1] - 1e-6 for i in range(len(profile) - 1)):
        problems.append("the boundary is not monotone")
    # THE THREE FACTS 10c GOT WRONG.
    if abs(float(inset_figma(params["p"], RADIUS, smoothing))) > 0.01:
        problems.append("the curve does not meet the left edge at p")
    if abs(float(inset_figma(0.0, RADIUS, smoothing)) - params["p"]) > 0.01:
        problems.append("the curve does not reach the top edge at p")
    # The middle of the corner IS the circle: the smoothing changes the transitions, not the arc.
    for k in (5, 10):
        if abs(expected[k] - float(inset_circle(k, RADIUS))) > 0.01:
            problems.append(f"the arc at y={k} is not the circle ({expected[k]:.3f})")
    fields = (f"p={_fmt(params['p'])} extent={extent} sweep_err_max={_fmt(max(errors), 3)}"
              f" x_at_y_1={_fmt(measured['x_at_y'][1])} x_at_y_5={_fmt(measured['x_at_y'][5])}"
              f" x_at_y_10={_fmt(measured['x_at_y'][10])}"
              f" circle_x_at_y_1={_fmt(float(inset_circle(1, RADIUS)))}"
              f" flat_run={measured['flat_run']}")
    return problems, fields


def _case_frame():
    """The frame-of-reference guard: the same corner, offset in a canvas and mirrored."""
    base = render_corner(inside_circle, RADIUS, ss=RENDER_SS)
    reference = measure_corner(base, int(RADIUS))
    problems = []
    fields = []
    offset = np.zeros((base.shape[0] + 9, base.shape[1] + 12))
    offset[5:5 + base.shape[0], 7:7 + base.shape[1]] = base
    moved = measure_corner(offset, int(RADIUS))
    if moved["vertex"] != (7, 5):
        problems.append(f"vertex recovered as {moved['vertex']}, expected (7, 5)")
    err = max(abs(a - b) for a, b in zip(moved["profile"], reference["profile"]))
    if err > 0.05:
        problems.append(f"the offset profile moved by {err:.3f}")
    fields.append(f"vertex={moved['vertex'][0]},{moved['vertex'][1]} profile_err_max={_fmt(err, 3)}")

    mirrored = measure_corner(base[:, ::-1], int(RADIUS), corner="tr")
    err_m = max(abs(a - b) for a, b in zip(mirrored["profile"], reference["profile"]))
    if err_m > 0.05:
        problems.append(f"the mirrored profile moved by {err_m:.3f}")
    fields.append(f"corner=tr profile_err_max={_fmt(err_m, 3)}")
    return problems, " ".join(fields)


def _case_refuse_empty():
    """A malformed input must be REFUSED: an all-background image has no corner to measure."""
    try:
        measure_corner(np.zeros((40, 40)), int(RADIUS))
    except FrameError as exc:
        return [], f"refused=empty reason={str(exc).split(':')[0].replace(' ', '_')}"
    return ["an empty image was measured instead of refused"], "refused=no"


def _case_image_png():
    """The FILE adapter must recover the same shape as the in-memory render.

    This case exists because the adapter was wrong twice on its first run, and both bugs were
    invisible to the pixel reader: the automatic background took a median of ALL FOUR borders
    (on a corner crop the window touches two of them, so the mask came out inverted and the tool
    refused its own render), and a distance threshold saturated the alpha ramp (x=6.00 at y=5
    where the arc is at 6.77). Neither would have been caught by a self-test that only measured
    arrays in memory.
    """
    coverage = render_corner(inside_circle, RADIUS, ss=RENDER_SS)
    handle = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    path = handle.name
    handle.close()
    try:
        Image.fromarray((np.stack([coverage] * 3, axis=2) * 255).astype("uint8")).save(path)
        measured = measure_corner(coverage_from_image(path, "tl"), int(RADIUS))
    finally:
        os.unlink(path)
    expected = float(inset_circle(5, RADIUS))
    error = abs(measured["x_at_y"][5] - expected)
    problems = []
    if error > 0.25:
        problems.append(f"the PNG adapter read {measured['x_at_y'][5]:.2f} at y=5, the arc is at {expected:.2f}")
    fields = (f"x_at_y_5={_fmt(measured['x_at_y'][5])} expected={_fmt(expected)}"
              f" flat_run={measured['flat_run']}")
    return problems, fields


def _case_realistic():
    """The REAL capture's shape: a light title band over a dark client, on a GRADIENT background, in
    a wide crop.

    This is the case that first refused and then measured the corner 4 px out, and it locks in both
    fixes it forced: the window's colour must be sampled JUST INSIDE the edge (the bottom row is the
    dark content, and the coarse bounding box can start on a bright patch of wallpaper), and the
    measurement must be done on a LOCAL crop (a wallpaper gradient across a wide capture otherwise
    reads as a window at the far end -- x=828 of 1043 on the real one).
    """
    R, s = 20.0, SUPERELLIPSE_SMOOTHING
    h, w = 180, 360
    vertex_x, vertex_y, band = 60, 60, 44
    xs = np.linspace(0.0, 1.0, w)
    gradient = np.stack([0.30 + 0.14 * xs, 0.58 + 0.10 * xs, 0.85 + 0.03 * xs], axis=1)
    image = np.repeat(gradient[None, :, :], h, axis=0)
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    local_y = yy - vertex_y
    inset = inset_figma(np.clip(local_y, 0.0, None), R, s)
    window = (yy >= vertex_y) & (xx >= vertex_x) & (xx >= vertex_x + inset)
    is_band = (local_y >= 0.0) & (local_y < band)
    colour = np.where(is_band[..., None], np.array([0.61, 0.81, 0.90]),
                      np.array([0.10, 0.11, 0.12]))
    image = np.where(window[..., None], colour, image)
    handle = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    path = handle.name
    handle.close()
    try:
        Image.fromarray((np.clip(image, 0.0, 1.0) * 255).astype("uint8")).save(path)
        measured = measure_corner(coverage_from_image(path, "tl", radius=R), int(R))
    finally:
        os.unlink(path)
    expected = {k: float(inset_figma(k, R, s)) for k in (1, 5, 10)}
    errors = [abs(measured["x_at_y"][k] - expected[k]) for k in expected]
    problems = []
    if max(errors) > 0.4:
        problems.append(f"a gradient capture measured the corner {max(errors):.3f} px out")
    fields = (f"sweep_err_max={_fmt(max(errors), 3)} x_at_y_5={_fmt(measured['x_at_y'][5])}"
              f" expected={_fmt(expected[5])} vertex={measured['vertex'][0]},{measured['vertex'][1]}")
    return problems, fields


def _case_curvature():
    """The curvature instrument, judged FIRST on cases whose answer is known by definition.

    A circular arc has CONSTANT curvature 1/R, so the instrument must call it continuous and read
    1/R. The Figma construction is the curve on screen today, and its curvature SPIKE is the "angle"
    the user sees in the highlight; the instrument must FLAG it. If it cannot tell those two apart it
    cannot judge a replacement either -- which is the whole reason this case exists before any
    candidate is written.
    """
    problems = []
    arc = curvature_verdict(circle_arc_points(RADIUS), RADIUS)
    if arc["spike"]:
        problems.append(f"a circular arc was called non-continuous ({arc['overshoot_pct']:+.1f}% over)")
    if abs(arc["curvature_max"] - 1.0 / RADIUS) > 0.02 / RADIUS:
        problems.append(f"the arc read {arc['curvature_max']:.5f}, 1/R is {1.0 / RADIUS:.5f}")
    figma = curvature_verdict(figma_curve(RADIUS, SUPERELLIPSE_SMOOTHING, samples=2000), RADIUS)
    if not figma["spike"]:
        problems.append("the Figma curve's curvature spike was NOT detected: the instrument cannot "
                        "see what the user sees, so it cannot judge its replacement")
    if figma["overshoot_pct"] < 20.0:
        problems.append(f"the Figma spike read {figma['overshoot_pct']:+.1f}%, expected about +47%")
    fields = (f"arc_max={_fmt(arc['curvature_max'], 5)} (1/R={_fmt(1.0 / RADIUS, 5)})"
              f" figma_max={_fmt(figma['curvature_max'], 5)}"
              f" figma_overshoot={_fmt(figma['overshoot_pct'], 1)}%"
              f" figma_spike={figma['spike']}"
              f" arc_maxima={arc['maxima']} figma_maxima={figma['maxima']}")
    return problems, fields


def self_test():
    cases = (
        ("circle", _case_circle),
        ("flat", _case_flat),
        ("spike", _case_spike),
        ("apple", _case_apple),
        ("curvature", _case_curvature),
        ("frame", _case_frame),
        ("image_png", _case_image_png),
        ("realistic", _case_realistic),
        ("refuse_empty", _case_refuse_empty),
    )
    failed = 0
    for name, fn in cases:
        try:
            problems, fields = fn()
        except Exception as exc:   # a case that cannot even run is a failed case, named
            problems, fields = [f"{type(exc).__name__}: {exc}"], ""
        verdict = "ok" if not problems else "fail"
        failed += bool(problems)
        print(f"case={name} verdict={verdict} {fields}".rstrip())
        for problem in problems:
            print(f"  {name}: {problem}")
    if failed:
        print(f"self-test: {failed} case(s) failed", file=sys.stderr)
        return 1
    return 0


# --------------------------------------------------------------------------------------------
# The screenshot path. NOT yet validated against a real capture: 10c says the known-value case
# comes first. It is here so the next session points it at an effect-off crop and refines it.
# --------------------------------------------------------------------------------------------
def _corner_edges(rgb, corner):
    """The two edges at the OUTER vertex (background) and the two INNER ones (the window)."""
    outer = {"tl": (rgb[0], rgb[:, 0]), "tr": (rgb[0], rgb[:, -1]),
             "bl": (rgb[-1], rgb[:, 0]), "br": (rgb[-1], rgb[:, -1])}[corner]
    inner = {"tl": (rgb[-1], rgb[:, -1]), "tr": (rgb[-1], rgb[:, 0]),
             "bl": (rgb[0], rgb[:, -1]), "br": (rgb[0], rgb[:, 0])}[corner]
    return outer, inner


def _walk_diagonal(rgb, background, corner):
    """First strong background-to-window rise along the INWARD DIAGONAL from the outer vertex.

    Returns (index, window colour just past the rise), or (None, None). This is the sample that had
    to replace three wrong ones: the bottom row is dark CONTENT rather than the title band, a coarse
    bounding box can start on a bright patch of wallpaper, and a fixed offset is still outside a
    rounded corner. The first rise is the background-to-window step whatever the window's colour.
    """
    h, w = rgb.shape[:2]
    y_start = 0 if corner in ("tl", "tr") else h - 1
    x_start = 0 if corner in ("tl", "bl") else w - 1
    y_step = 1 if corner in ("tl", "tr") else -1
    x_step = 1 if corner in ("tl", "bl") else -1
    n = min(h, w)
    diagonal = np.array([np.linalg.norm(rgb[min(max(y_start + y_step * i, 0), h - 1),
                                            min(max(x_start + x_step * i, 0), w - 1)] - background)
                         for i in range(n)])
    steps = np.diff(diagonal)
    if steps.size == 0 or float(steps.max()) < 0.02:
        return None, None
    i_edge = int(np.argmax(steps > 0.25 * float(steps.max())))
    i_sample = min(i_edge + 3, n - 1)
    y = min(max(y_start + y_step * i_sample, 0), h - 1)
    x = min(max(x_start + x_step * i_sample, 0), w - 1)
    patch = rgb[max(y - 2, 0):y + 3, max(x - 2, 0):x + 3].reshape(-1, 3)
    if patch.size == 0:
        return None, None
    return i_edge, np.median(patch, axis=0)


def coverage_from_image(path, corner="tl", background=None, tolerance=0.15, radius=20.0):
    """Coverage of the window against its background, for a corner crop.

    MEASURED ON A LOCAL CROP, not on the whole image. A wallpaper has a gradient across a wide
    capture, and on the first real one (1043 px) that gradient alone exceeded the glass-to-wallpaper
    step at the far end: the frame check found a "window" at x=828. The shape is local, so the
    background, the edge and the window's colour are all taken within a few radii of the corner.
    """
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=float) / 255.0
    outer, _inner = _corner_edges(rgb, corner)
    if background is None:
        # THE BACKGROUND LIVES OUTSIDE THE CORNER: the two edges that meet at the outer vertex, not
        # the median of all four. On a corner crop the window touches the two INNER edges.
        background = np.median(np.concatenate(outer), axis=0)
    i_edge, _ = _walk_diagonal(rgb, background, corner)
    if i_edge is None:
        return np.zeros(rgb.shape[:2])
    y_step = 1 if corner in ("tl", "tr") else -1
    x_step = 1 if corner in ("tl", "bl") else -1
    yc = (0 if corner in ("tl", "tr") else rgb.shape[0] - 1) + y_step * i_edge
    xc = (0 if corner in ("tl", "bl") else rgb.shape[1] - 1) + x_step * i_edge
    pad_in, pad_out = int(1.5 * radius) + 4, int(2.5 * radius) + 8
    h, w = rgb.shape[:2]
    y0 = max(yc - (pad_in if y_step > 0 else pad_out), 0)
    y1 = min(yc + (pad_out if y_step > 0 else pad_in), h)
    x0 = max(xc - (pad_in if x_step > 0 else pad_out), 0)
    x1 = min(xc + (pad_out if x_step > 0 else pad_in), w)
    sub = rgb[y0:y1, x0:x1]
    outer_sub, _inner_sub = _corner_edges(sub, corner)
    sub_background = np.median(np.concatenate(outer_sub), axis=0)
    _ie, foreground = _walk_diagonal(sub, sub_background, corner)
    distance = np.linalg.norm(sub - sub_background, axis=2)
    span = float(np.linalg.norm(foreground - sub_background)) if foreground is not None else 0.0
    if span < 0.05:
        # the window and its background are the same colour: fall back to the caller's threshold
        return np.clip(distance / max(tolerance, 1e-6), 0.0, 1.0)
    return np.clip(distance / span, 0.0, 1.0)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true",
                        help="run the synthetic known-value cases and exit non-zero on failure")
    parser.add_argument("--image", help="a screenshot crop of the corner (validated on synthetic "
                                        "captures; ~0.3 px accuracy on a real one)")
    parser.add_argument("--corner", default="tl", choices=("tl", "tr", "bl", "br"))
    parser.add_argument("--radius", type=float, default=RADIUS)
    parser.add_argument("--background", help="auto by default; else 'R,G,B' in 0..255")
    parser.add_argument("--tolerance", type=float, default=0.15)
    parser.add_argument("--smoothing", type=float, default=SUPERELLIPSE_SMOOTHING,
                        help="the kit's cornerSmoothing, for the curves that take one")
    parser.add_argument("--curvature", metavar="CURVE",
                        help="judge a named corner curve's curvature profile and exit: "
                             "circle | figma | superellipse:N | g2bezier")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if args.curvature:
        name = args.curvature
        if name == "circle":
            points = circle_arc_points(args.radius)
        elif name == "figma":
            points = figma_curve(args.radius, args.smoothing, samples=4000)
        elif name.startswith("superellipse"):
            n = float(name.split(":")[1]) if ":" in name else 4.0
            points = superellipse_arc_points(args.radius, n)
        elif name == "g2bezier":
            points = g2_bezier_corner_points(args.radius, 90.0 * (1.0 - args.smoothing),
                                             (1.0 + args.smoothing) * args.radius)
        elif name == "clothoid":
            points = clothoid_corner_points(args.radius, 90.0 * (1.0 - args.smoothing))
        else:
            parser.error(f"unknown curve '{name}'")
        v = curvature_verdict(points, args.radius)
        print(f"curve={name} radius={args.radius:g} smoothing={args.smoothing:g}"
              f" kappa_min={v['curvature_min']:.5f} kappa_max={v['curvature_max']:.5f}"
              f" arc={v['arc_curvature']:.5f} overshoot_pct={v['overshoot_pct']:+.1f}"
              f" spike={v['spike']} maxima={v['maxima']}")
        return 0
    if not args.image:
        parser.error("one of --self-test or --image is required")

    background = None
    if args.background and args.background != "auto":
        background = np.array([float(v) / 255.0 for v in args.background.split(",")])
    coverage = coverage_from_image(args.image, args.corner, background, args.tolerance, args.radius)
    try:
        measured = measure_corner(coverage, int(round(args.radius)), corner=args.corner)
    except FrameError as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return 2
    print(f"image={args.image}")
    print(f"corner={args.corner} radius={args.radius:g}")
    print(f"vertex={measured['vertex'][0]},{measured['vertex'][1]}")
    for k, value in measured["x_at_y"].items():
        print(f"x_at_y_{k}={value:.2f}")
    print(f"missing_area={measured['missing_area']:.2f}")
    print(f"flat_run={measured['flat_run']}")
    print(f"diagonal_minus_radius={measured['diagonal_minus_radius']:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

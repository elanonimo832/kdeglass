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
import sys

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


def self_test():
    cases = (
        ("circle", _case_circle),
        ("flat", _case_flat),
        ("spike", _case_spike),
        ("frame", _case_frame),
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
def coverage_from_image(path, background=None, tolerance=0.15):
    image = Image.open(path).convert("RGB")
    rgb = np.asarray(image, dtype=float) / 255.0
    if background is None:
        border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
        background = np.median(border, axis=0)
    distance = np.linalg.norm(rgb - background, axis=2)
    return np.clip(distance / max(tolerance, 1e-6), 0.0, 1.0)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true",
                        help="run the synthetic known-value cases and exit non-zero on failure")
    parser.add_argument("--image", help="a screenshot crop of the corner (unvalidated path)")
    parser.add_argument("--corner", default="tl", choices=("tl", "tr", "bl", "br"))
    parser.add_argument("--radius", type=float, default=RADIUS)
    parser.add_argument("--background", help="auto by default; else 'R,G,B' in 0..255")
    parser.add_argument("--tolerance", type=float, default=0.15)
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.image:
        parser.error("one of --self-test or --image is required")

    background = None
    if args.background and args.background != "auto":
        background = np.array([float(v) / 255.0 for v in args.background.split(",")])
    coverage = coverage_from_image(args.image, background, args.tolerance)
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

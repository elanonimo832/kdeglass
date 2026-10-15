#!/usr/bin/env python3
"""Measures the backdrop's BEND along each of the band's four edges, and checks the shader's own
direction logic against the simulator's.

WHY THIS EXISTS. The bend's direction came from the gradient of the FRAME's rounded distance alone.
That distance is FLAT -- gradient zero -- in the interior of the band's BOTTOM edge, because the
bottom edge is the top of the content and is not an edge of the frame at all. So the shader bent
nothing along the bottom, while the simulator (which uses the whole box) always bent there: the two
implementations disagreed, and the user saw it on screen -- vertical backdrop lines stayed vertical
with nothing bending them along the band's bottom edge.

THE SHADER CANNOT BE RUN HERE, so `shader_shift()` is a TRANSCRIPTION of its expressions, kept named
next to the quantities the simulator returns. A transcription can drift from the GLSL, so
`tests/test-glass.sh` also asserts that the shader's source contains the same expressions this file
transcribes; the measurement and the text check each other.

    python3 measure-refraction.py --self-test
"""
import argparse
import importlib.util
import math
import pathlib
import sys

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("simulate", HERE / "simulate.py")
sim = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sim)

# A REAL window and band, the Konsole the handoff measured: the shader's frame distance only means
# anything with the frame's real proportions in it.
WINDOW_W, WINDOW_H = 905.0, 758.0
BAR = 38   # the measured title bar height in the handoff's Konsole log
RADIUS = float(sim.DEFAULTS.get("CornerRadius", 20.0))
REFRACTION = float(sim.DEFAULTS.get("Refraction", 20.0))
REACH = float(sim.DEFAULTS.get("RefractionReach", 24.0))
RIM = float(sim.DEFAULTS.get("RimWidth", 12.0))


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def shader_shift(x, y, w=WINDOW_W, h=WINDOW_H, bar=BAR, radius=RADIUS,
                 refraction=REFRACTION, reach=REACH):
    """The bend the SHADER computes, transcribed from src/glass.cpp, in IMAGE coordinates (y down).

    The shader's `cornerPos.y` is BOTTOM-UP (vTexCoord.y is 1 at the top), so `Y = h - y` here; every
    quantity below is a line of the GLSL with the same name. The result is the displacement of the
    backdrop sampled at this fragment, in image coordinates: +x is right, +y is DOWN.
    """
    corner_pos = np.array([x, h - y])
    corner_half = np.array([w * 0.5, h * 0.5])
    q = np.abs(corner_pos - corner_half) - (corner_half - radius)
    # the circle branch: `qNormal = max(q, 0)`, `edgeDistance` the standard rounded-box distance
    corner_distance = float(np.hypot(max(q[0], 0.0), max(q[1], 0.0)))
    edge_distance = -(corner_distance + min(max(q[0], q[1]), 0.0) - radius)
    # THE BAND'S OWN BOTTOM, the edge the frame's distance knows nothing about
    band_edge = bar - y
    gradiente = np.maximum(q, 0.0) * np.sign(corner_pos - corner_half)
    g_len = float(np.hypot(gradiente[0], gradiente[1]))
    frame_inward = (-gradiente / g_len) if g_len > 1e-6 else np.zeros(2)
    # the blend: each edge weighted by its own proximity, the magnitude the stronger of the two
    w_frame = 1.0 - smoothstep(0.0, reach, edge_distance)
    w_bottom = 1.0 - smoothstep(0.0, reach, band_edge)
    blended = w_frame * frame_inward + w_bottom * np.array([0.0, 1.0])
    b_len = float(np.hypot(blended[0], blended[1]))
    inward = (blended / b_len) if b_len > 1e-6 else np.zeros(2)
    bend = max(w_frame, w_bottom)
    # +x in the capture is +x on screen; +v is UP, so a positive inward.y samples higher and shows
    # the backdrop shifted DOWN. That is the whole sign convention, in one line.
    return np.array([inward[0], -inward[1]]) * refraction * bend



def simulator_shift(x, y, bar=BAR, w=WINDOW_W, radius=RADIUS, smoothing=0.0,
                    refraction=REFRACTION, reach=REACH, rim=RIM):
    """The same displacement from the SIMULATOR's own code, so the two can be compared."""
    shift_x, shift_y, _to_edge, _rim, _refract = sim.refraction_field(
        int(bar), int(w), radius, smoothing, rim, reach, refraction)
    return np.array([shift_x[int(y), int(x)], shift_y[int(y), int(x)]])


def edge_samples(w=WINDOW_W, bar=BAR):
    """Midpoints of the four edges, away from the corners where the models round differently."""
    # INTEGERS, because the simulator's field lives on a pixel grid and comparing a float sample
    # against the nearest pixel invented a 0.8 px mismatch on the sides that was pure sampling.
    mid, quarter, three = int(w * 0.5), int(w * 0.25), int(w * 0.75)
    return {
        "top": [(mid, 1), (quarter, 1), (three, 1)],
        "bottom": [(mid, bar - 1), (quarter, bar - 1), (three, bar - 1)],
        "left": [(1, bar // 2), (1, bar // 4), (1, 3 * bar // 4)],
        "right": [(int(w) - 1, bar // 2), (int(w) - 1, bar // 4), (int(w) - 1, 3 * bar // 4)],
    }


def edge_report(edge):
    """(shader magnitude, shader direction, simulator magnitude, mismatch) for one edge."""
    sh, si, mismatch = [], [], []
    for x, y in edge_samples()[edge]:
        a = shader_shift(x, y)
        b = simulator_shift(x, y)
        sh.append(float(np.hypot(a[0], a[1])))
        si.append(float(np.hypot(b[0], b[1])))
        mismatch.append(float(np.hypot(a[0] - b[0], a[1] - b[1])))
    return float(np.mean(sh)), float(np.mean(si)), float(np.max(mismatch))


def self_test():
    """Every edge must bend, and the shader's bend must be the simulator's bend."""
    problems = []
    parity = 0.0
    for edge in ("top", "bottom", "left", "right"):
        sh, si, mm = edge_report(edge)
        parity = max(parity, mm)
        # A BEND, not a nudge: with the refraction at its default and the falloff near 1 at the edge
        # itself, every edge is expected in the tens of pixels. 5 px is a floor, not a target.
        if sh < 5.0:
            problems.append(f"the {edge} edge bends {sh:.2f} px in the shader (a bend is expected)")
        if si < 5.0:
            problems.append(f"the {edge} edge bends {si:.2f} px in the simulator")
        if mm > 0.5:
            problems.append(f"the {edge} edge: shader and simulator differ by {mm:.2f} px")
        print(f"case=edge_{edge} shader={sh:.2f} simulator={si:.2f} mismatch={mm:.2f}")
    # THE BOTTOM EDGE'S DIRECTION, which is the whole point of this file: it must be VERTICAL. A
    # horizontal component there would be a diagonal bend, which is what an earlier fix produced.
    bx, by = shader_shift(int(WINDOW_W * 0.5), BAR - 1)
    if abs(bx) > 0.5 or by >= 0.0:
        problems.append(f"the bottom edge bends ({bx:.2f}, {by:.2f}); it must be vertical and upward")
    print(f"bottom_direction x={bx:.3f} y={by:.3f} (must be vertical and upward)")
    print(f"parity_max_mismatch={parity:.3f} px")
    for p in problems:
        print(f"  {p}", file=sys.stderr)
    if problems:
        print("measure-refraction: SELF-TEST FAILED", file=sys.stderr)
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--RefractionReach", type=float, default=REACH)
    args = ap.parse_args()
    if args.RefractionReach != REACH:
        globals()["REACH"] = args.RefractionReach
    if args.self_test:
        return self_test()
    ap.error("--self-test is the instrument; there is nothing else to ask it yet")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

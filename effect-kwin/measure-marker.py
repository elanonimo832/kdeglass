#!/usr/bin/env python3
"""Verify the M1.1 marker by DIFFERENCE, not by colour.

Why not by colour: KWin composites through its own colour pipeline, so the exact
value written with glClearColor is NOT the value that reaches the screen. In the
200 px run we wrote 0x00E5FF and measured #215055 -- a completely different
colour and much darker. An exact-colour check therefore fails on a marker that is
plainly visible, which is how this was first misdiagnosed as "does not draw".

What is robust is the DIFFERENCE between two screenshots: with the effect off and
with it on. The marker is the only thing that changes, and its size is known.

Usage: measure-marker.py <control.png> <loaded.png> [expected_px]
"""
import sys
from PIL import Image
import numpy as np

if len(sys.argv) < 3:
    print("usage: measure-marker.py <control.png> <loaded.png> [expected_px]")
    raise SystemExit(2)

control = np.array(Image.open(sys.argv[1]).convert("RGB")).astype(int)
loaded = np.array(Image.open(sys.argv[2]).convert("RGB")).astype(int)
expected = int(sys.argv[3]) if len(sys.argv) > 3 else 48 * 48

if control.shape != loaded.shape:
    print(f"  screenshots differ in size: {control.shape} vs {loaded.shape}")
    raise SystemExit(2)

# Threshold 40 on the summed channel difference: above screenshot noise (cursor,
# clock, antialiasing) and below a deliberate colour patch.
diff = np.abs(loaded - control).sum(axis=2)
changed = diff > 40
n = int(changed.sum())

print(f"  control : {sys.argv[1]}")
print(f"  loaded  : {sys.argv[2]}")
print(f"  {control.shape[1]}x{control.shape[0]}")
print(f"  changed : {n} px  (one {int(expected**0.5)}x{int(expected**0.5)} patch is {expected} px)")
if n:
    ys, xs = np.where(changed)
    print(f"  bounding box: x {xs.min()}-{xs.max()}  y {ys.min()}-{ys.max()}")

print()
# A single patch is `expected` px. Several windows means a multiple of it. Demand
# at least half of one patch: enough to reject noise, tolerant of a window partly
# off-screen or partly covered.
if n >= expected // 2:
    print(f"  VERDICT: THE MARKER IS DRAWN ({n} px >= {expected // 2})")
    raise SystemExit(0)
print(f"  VERDICT: NOT drawn ({n} px < {expected // 2})")
raise SystemExit(1)

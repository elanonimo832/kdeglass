#!/usr/bin/env python3
"""M1.2b: the material covers the TITLE BAR and leaves the content sharp.

Two screenshots of the same window -- one with the effect off, one on -- plus the
window's geometry. It checks the two halves separately:

    title bar band : edge energy must FALL (the material blurs it)
    content area   : edge energy must STAY (you have to be able to read it)

A single whole-window measurement cannot tell these apart, which is why the
full-window version passed its test and still made the window unreadable.

M1.3a STEP 2 CHANGES WHAT "APPLIED" LOOKS LIKE, so read the verdict carefully.
In step 2 the band shows the CAPTURED DESKTOP, which is sharp: edge energy does not
fall, and this used to print "NOT APPLIED" for an effect that was plainly working.
That state has its own verdict and its own exit code (3) now. The blur returns in
step 3, and then the criterion above applies again.

Exit codes: 0 correct, 1 a problem (or not applied), 2 cannot measure,
            3 the band changed but kept its detail -- what the captured desktop looks
              like when it is NOT blurred (M1.3a step 2, where BackgroundRadius is 0)

Usage: measure-titlebar.py <off.png> <on.png> <x> <y> <w> <h> <barHeight>
  x y w h are the window's frame geometry in device pixels; barHeight is the
  title bar height, printed by the effect as "barHeight=" in the journal.
"""
import sys
from PIL import Image
import numpy as np


def edge_energy(a):
    """Variance of the Laplacian: high-frequency detail. A blur removes it."""
    lum = 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]
    if lum.shape[0] < 3 or lum.shape[1] < 3:
        return 0.0
    lap = (-4.0 * lum[1:-1, 1:-1]
           + lum[:-2, 1:-1] + lum[2:, 1:-1]
           + lum[1:-1, :-2] + lum[1:-1, 2:])
    return float(lap.var())


def main():
    if len(sys.argv) < 8:
        print(__doc__)
        return 2
    off = np.array(Image.open(sys.argv[1]).convert("RGB")).astype(float)
    on = np.array(Image.open(sys.argv[2]).convert("RGB")).astype(float)
    x, y, w, h = (int(v) for v in sys.argv[3:7])
    bar = int(sys.argv[7])

    # a couple of pixels of margin so the frame edge does not dominate
    m = 3
    band_off = off[y + m:y + bar - m, x + m:x + w - m]
    band_on = on[y + m:y + bar - m, x + m:x + w - m]
    body_off = off[y + bar + m:y + h - m, x + m:x + w - m]
    body_on = on[y + bar + m:y + h - m, x + m:x + w - m]

    if band_off.size == 0 or body_off.size == 0:
        print("  window geometry does not fit the screenshot; check x y w h")
        return 2

    eb_off, eb_on = edge_energy(band_off), edge_energy(band_on)
    ec_off, ec_on = edge_energy(body_off), edge_energy(body_on)

    print(f"  window: x{x} y{y} {w}x{h}, title bar {bar} px")
    print()
    print(f"  {'region':14s} {'off':>10s} {'on':>10s} {'change':>10s}")
    print(f"  {'title bar':14s} {eb_off:10.1f} {eb_on:10.1f} "
          f"{(eb_on - eb_off) / eb_off * 100 if eb_off else 0:+9.1f} %")
    print(f"  {'content':14s} {ec_off:10.1f} {ec_on:10.1f} "
          f"{(ec_on - ec_off) / ec_off * 100 if ec_off else 0:+9.1f} %")
    print()

    if eb_off <= 0 or ec_off <= 0:
        print("  VERDICT: cannot measure (a region has no detail to lose)")
        return 2
    band_drop = (eb_off - eb_on) / eb_off
    body_drop = (ec_off - ec_on) / ec_off

    if band_drop >= 0.25 and body_drop < 0.15:
        print(f"  VERDICT: CORRECT. title bar blurred {band_drop * 100:.1f} %, "
              f"content intact ({body_drop * 100:.1f} %)")
        return 0
    if band_drop >= 0.25 and body_drop >= 0.15:
        print(f"  VERDICT: TOO WIDE. content is blurred too ({body_drop * 100:.1f} %)")
        return 1

    # Distinguish "nothing happened" from "something happened that is not a blur".
    # The per-pixel difference is the robust question here: two different sharp
    # images differ everywhere, an untouched band differs nowhere.
    cambio = float(np.abs(band_on - band_off).mean())
    if cambio >= 8.0:
        print(f"  VERDICT: THE BAND CHANGED ({cambio:.1f} mean per-pixel) BUT KEPT ITS DETAIL")
        print("    The effect is drawing something with as much detail as the bar had.")
        print("    That is what the captured desktop looks like when it is NOT blurred")
        print("    (M1.3a step 2, and the default: BackgroundRadius = 0). If the band is")
        print("    supposed to be frosted, this says the blur is not in the path.")
        print("    It is not the same as 'not applied', and it is not a regression.")
        return 3

    print(f"  VERDICT: NOT APPLIED. title bar only fell {band_drop * 100:.1f} %")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

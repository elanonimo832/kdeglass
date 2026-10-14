#!/usr/bin/env python3
"""Measure DIFFUSION by local contrast, not by colour.

Why not by colour: M1.1 showed that colour survives compositing in ways you
cannot predict (0x00E5FF measured as #215055). Why not by difference either: a
difference tells you something changed, not WHAT changed.

What a blur actually does is remove high-frequency detail. So:

    local contrast (standard deviation of pixel values) DROPS
    global brightness (mean) stays roughly the same

That is the definition being tested. A tint or a flat patch changes the mean and
leaves the standard deviation alone, so this measurement cannot be faked by the
M1.1 mechanism.

Usage: measure-diffusion.py <control.png> <loaded.png> [x y w h]
The optional rectangle restricts the comparison to a window's area; without it,
the whole screenshots are used and MOVING CONTENT will swamp the result.
"""
import sys
from PIL import Image
import numpy as np


def stats(a):
    """Mean and standard deviation of luminance, plus a high-frequency measure."""
    # Rec. 709 luma
    lum = 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]
    # Local high-frequency energy: the Laplacian's variance. A blur removes it,
    # and unlike plain standard deviation it is insensitive to a smooth gradient.
    lap = (
        -4.0 * lum[1:-1, 1:-1]
        + lum[:-2, 1:-1] + lum[2:, 1:-1] + lum[1:-1, :-2] + lum[1:-1, 2:]
    )
    return float(lum.mean()), float(lum.std()), float(lap.var())


def main():
    if len(sys.argv) < 3:
        print("usage: measure-diffusion.py <control.png> <loaded.png> [x y w h]")
        return 2

    control = np.array(Image.open(sys.argv[1]).convert("RGB")).astype(float)
    loaded = np.array(Image.open(sys.argv[2]).convert("RGB")).astype(float)

    if len(sys.argv) >= 7:
        x, y, w, h = (int(v) for v in sys.argv[3:7])
        control = control[y:y + h, x:x + w]
        loaded = loaded[y:y + h, x:x + w]
        print(f"  region: x{x} y{y} {w}x{h}")
    else:
        print(f"  region: whole image {control.shape[1]}x{control.shape[0]}")
        print("  WARNING: without a region, any moving content swamps the result")

    cm, cs, ce = stats(control)
    lm, ls, le = stats(loaded)

    print()
    print(f"  {'':10s} {'mean':>9s} {'std':>9s} {'edge energy':>13s}")
    print(f"  {'control':10s} {cm:9.2f} {cs:9.2f} {ce:13.2f}")
    print(f"  {'loaded':10s} {lm:9.2f} {ls:9.2f} {le:13.2f}")
    print()
    print(f"  mean change : {lm - cm:+8.2f}   (a blur should leave this small)")
    print(f"  std change  : {ls - cs:+8.2f}")
    if ce > 0:
        print(f"  edge energy : {(le - ce) / ce * 100:+7.1f} %   <- the diffusion signal")
    print()

    # Diffusion: high-frequency energy collapses while brightness is preserved.
    if ce <= 0:
        print("  VERDICT: cannot measure (control has no high-frequency energy)")
        return 2
    drop = (ce - le) / ce
    if abs(lm - cm) > 12:
        print(f"  VERDICT: brightness moved too much ({lm - cm:+.1f}); that is a tint, not a blur")
        return 1
    if drop >= 0.25:
        print(f"  VERDICT: DIFFUSED. edge energy fell {drop * 100:.1f} % with brightness preserved")
        return 0
    print(f"  VERDICT: NOT diffused. edge energy fell only {drop * 100:.1f} % (need >= 25 %)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

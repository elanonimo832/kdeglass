#!/usr/bin/env python3
"""M1.3a step 3d: is the band sampling the backdrop where it should?

WHY THIS EXISTS. Every size in the shader comes from frameGeometry(), while the texture
KWin redirects the window into covers expandedGeometry() -- frame PLUS the decoration's
shadow margins (measured on this theme: 14 px across, 7 px down). If the two disagree,
the band shows the backdrop displaced by that much, and against a wallpaper nobody can
see it. Against TEXT it is visible, which is why "put text behind the window" was the
instruction -- but looking at it cannot say how many pixels, and guessing is what this
project keeps having to unlearn.

HOW IT MEASURES, and why it can. The backdrop BEHIND the window is hidden, so the band
cannot be compared with it directly. It can be compared with the SAME backdrop just
outside the window, because a screenshot has both:
  - the rows of the band are compared with a strip of the same rows beside the window,
    so what has to carry the signal is horizontal structure: text lines, a table, a photo.
  - the columns of the band are compared with a strip of the same columns above or below
    the window, so what has to carry the signal there is vertical structure: window edges,
    columns of a page, a wallpaper pattern.
Both profiles are high-passed first: the bar's own smooth gradient would otherwise
dominate the correlation and pull every answer towards zero.

    python3 measure-alignment.py <screenshot.png> <x> <y> <w> <barHeight>

  x y w barHeight describe the TITLE BAR rectangle, as the effect prints them, and the
  effect must be in its sharp mode (BackgroundRadius=0) so the band is not blurred.

Output, and what the numbers mean:
    horizontal: 14   (+0.87)     positive: the band shows what belongs 14 px further RIGHT
    vertical:    7   (+0.91)     positive:                 ... 7 px further DOWN
    VERDICT: DISPLACED (14, 7)
A displacement of (0, 0) means the sampling agrees with the decoration and there is no
margin bug. Fewer than 25 px of window margin on the needed side, or a backdrop with no
structure, gives INCONCLUSIVE instead of a number invented from noise.
"""
import sys

import numpy as np
from PIL import Image

LAG_MAX = 24
MIN_STRIP = 24


def perfil_alto_paso(v, ancho=5):
    """Remove the slow part: what is left is the structure the correlation can use.

    The padding is not cosmetic. With `mode="same"` the moving average is divided by the
    full window even where it is truncated, so a perfectly FLAT profile comes out with a
    spike at each end -- and the correlator locked onto those spikes and reported an
    alignment for a flat backdrop with a comfortable 0.77. Reflecting the edges first
    makes a flat profile flat, which is the whole point of the check.
    """
    if len(v) < ancho * 2:
        return v - v.mean()
    relleno = np.pad(v, ancho // 2, mode="reflect")
    suave = np.convolve(relleno, np.ones(ancho) / ancho, mode="valid")
    return v - suave[:len(v)]


def mejor_retardo(a, b):
    """Lag L that best aligns a[i] with b[i - L], plus the correlation there."""
    a = (a - a.mean())
    b = (b - b.mean())
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na < 1e-6 or nb < 1e-6:
        return None, 0.0
    mejor, mejor_r = 0, -2.0
    for L in range(-LAG_MAX, LAG_MAX + 1):
        if L >= 0:
            x, y = a[L:], b[:len(b) - L]
        else:
            x, y = a[:L], b[-L:]
        if len(x) < 8:
            continue
        r = float(np.dot(x - x.mean(), y - y.mean()) / (np.linalg.norm(x - x.mean()) * np.linalg.norm(y - y.mean()) + 1e-9))
        if r > mejor_r:
            mejor, mejor_r = L, r
    return mejor, mejor_r


def main():
    if len(sys.argv) < 6:
        print(__doc__)
        return 2
    img = np.array(Image.open(sys.argv[1]).convert("RGB")).astype(float).mean(axis=2)
    H, W = img.shape
    x, y, w, bar = (int(v) for v in sys.argv[2:6])
    if x < 0 or y < 0 or w <= 0 or bar <= 0 or y + bar > H or x + w > W:
        print("  the band rectangle does not fit the screenshot; check x y w bar")
        return 2

    # The band's own profiles, away from the traffic lights (left) and from a centred
    # title (middle), so the chrome is not what gets correlated.
    col0, col1 = x + int(0.70 * w), x + w - 8
    banda_filas = img[y:y + bar, col0:col1].mean(axis=1)
    banda_cols = img[y:y + bar, x + 8:x + w - 8].mean(axis=0)

    # Reference beside the window, at the band's rows.
    ancho_ref = min(80, max(MIN_STRIP, w // 4))
    if x + w + 8 + ancho_ref <= W:
        ref_filas = img[y:y + bar, x + w + 8:x + w + 8 + ancho_ref].mean(axis=1)
    elif x - 8 - ancho_ref >= 0:
        ref_filas = img[y:y + bar, x - 8 - ancho_ref:x - 8].mean(axis=1)
    else:
        print("horizontal: 0")
        print("vertical: 0")
        print("  VERDICT: INCONCLUSIVE (no room beside the window for a reference)")
        return 2

    # Reference above (or below) the window, at the band's columns.
    alto_ref = min(80, max(MIN_STRIP, bar * 2))
    if y - 8 - alto_ref >= 0:
        ref_cols = img[y - 8 - alto_ref:y - 8, x + 8:x + w - 8].mean(axis=0)
    elif y + bar + 8 + alto_ref <= H:
        ref_cols = img[y + bar + 8:y + bar + 8 + alto_ref, x + 8:x + w - 8].mean(axis=0)
    else:
        ref_cols = None

    Lv, rv = mejor_retardo(perfil_alto_paso(banda_filas), perfil_alto_paso(ref_filas))
    if Lv is None:
        print("vertical: 0")
        print("  VERDICT: INCONCLUSIVE (no contrast in the rows beside the window)")
        return 2
    dy = -Lv

    if ref_cols is None:
        print(f"vertical: {dy}   ({rv:+.2f})")
        print("horizontal: 0")
        print("  VERDICT: INCONCLUSIVE (no room above or below for a column reference)")
        return 2
    Lh, rh = mejor_retardo(perfil_alto_paso(banda_cols), perfil_alto_paso(ref_cols))
    if Lh is None:
        print("horizontal: 0")
        print(f"vertical: {dy}   ({rv:+.2f})")
        print("  VERDICT: INCONCLUSIVE (no contrast in the columns above the window)")
        return 2
    dx = -Lh

    print(f"horizontal: {dx}   ({rh:+.2f})")
    print(f"vertical: {dy}   ({rv:+.2f})")
    print()
    # A displacement of a couple of pixels is rounding, not a margin bug: the margins here
    # are 14 and 7, and the correlation is on a high-passed profile, whose lag resolution
    # is a pixel at best.
    if abs(dx) <= 2 and abs(dy) <= 2:
        print("  VERDICT: ALIGNED. the band samples the backdrop where it belongs")
        return 0
    if max(abs(rh), abs(rv)) < 0.30:
        print("  VERDICT: INCONCLUSIVE. the best alignment is weak; the reference has no")
        print("           structure in that axis. Put something with text or edges behind")
        print("           the window and try again.")
        return 2
    print(f"  VERDICT: DISPLACED ({dx}, {dy}). the band shows what belongs {abs(dx)} px")
    print(f"           {'right' if dx > 0 else 'left'} and {abs(dy)} px {'down' if dy > 0 else 'up'}.")
    print("           Compare with the decoration's shadow margin, which is what the")
    print("           shader's frame-sized uniforms would get wrong.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

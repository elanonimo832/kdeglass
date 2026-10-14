#!/usr/bin/env python3
"""M1.3a: does the title bar SHOW what is behind the window?

The test that matters for glass is not "is it blurred" -- M1.2b was blurred and
invisible. It is "does the bar take colour from its surroundings". Blurring the
window's own texture cannot: a uniform bar blurred is the same uniform bar, which
is exactly why the user could only tell the effect was there because the text had
become unreadable.

So: move the window so its bar sits over two DIFFERENT backgrounds, with the effect
ON both times, and compare the bar's own pixels.

    the bar changes  -> it is translucent, and the background shows through
    the bar is identical -> it is opaque; whatever else it does, it is not glass

This works without needing an off screenshot, and it cannot be satisfied by any
amount of blurring of opaque content.

Usage: measure-glass.py <over-bg-1.png> <over-bg-2.png> <x> <y> <w> <barHeight>
  x y w describe the TITLE BAR rectangle in both screenshots.
"""
import sys
from PIL import Image
import numpy as np


def main():
    if len(sys.argv) < 7:
        print(__doc__)
        return 2
    a = np.array(Image.open(sys.argv[1]).convert("RGB")).astype(float)
    b = np.array(Image.open(sys.argv[2]).convert("RGB")).astype(float)
    x, y, w, bar = (int(v) for v in sys.argv[3:7])

    # a few pixels of margin: the frame edge is decoration, not glass
    m = 4
    ra = a[y + m:y + bar - m, x + m:x + w - m]
    rb = b[y + m:y + bar - m, x + m:x + w - m]
    if ra.size == 0 or rb.size == 0:
        print("  the band rectangle does not fit the screenshots; check x y w bar")
        return 2

    ma = ra.reshape(-1, 3).mean(axis=0)
    mb = rb.reshape(-1, 3).mean(axis=0)
    delta = float(np.abs(ma - mb).mean())

    print(f"  band: x{x} y{y} {w}x{bar}")
    print(f"  over background 1: #{int(ma[0]):02X}{int(ma[1]):02X}{int(ma[2]):02X}")
    print(f"  over background 2: #{int(mb[0]):02X}{int(mb[1]):02X}{int(mb[2]):02X}")
    print(f"  mean channel difference: {delta:.1f}")
    print()

    # An opaque bar over two backgrounds differs only by the small amount of the
    # background that bleeds through its antialiasing: a couple of units. A
    # translucent one moves by tens.
    if delta >= 12:
        print(f"  VERDICT: GLASS. the bar takes colour from behind it ({delta:.1f})")
        return 0
    if delta >= 5:
        print(f"  VERDICT: slightly translucent ({delta:.1f}); raise the alpha contrast")
        return 1
    print(f"  VERDICT: OPAQUE. the bar looks the same over both backgrounds ({delta:.1f})")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

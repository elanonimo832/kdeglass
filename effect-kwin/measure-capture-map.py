#!/usr/bin/env python3
"""Where the capture's sub-rectangle mapping lands, for the two capture extents.

WHY THIS EXISTS. The shader turns the window's own texture coordinate into a coordinate of the
captured region with

    uvBackground = uBackgroundOffset + vTexCoord * uBackgroundScale

and `uBackgroundScale`/`uBackgroundOffset` are built from the FRAME and the REGION. The v axis of
both textures is BOTTOM-UP -- that is why the shader's distance from the window's top is
`(1 - vTexCoord.y) * uTextureSize.y` -- so the offset must measure the frame's BOTTOM from the
region's BOTTOM.

With the whole expanded geometry as the region the two origins differ by only the shadow margins
(2 px top against 2 px bottom here), and the wrong expression passed every check that was run at
the time. With the BAND as the region -- the same texture cropped to `bandHeight + 2*reach`, 126 px
instead of 762 -- the two differ by hundreds of pixels, and the wrong one sends every band fragment
to `uv.y = 6.35`: outside the texture, clamped to one row, which the frost then smears
horizontally. That is the difference between "the backdrop is blurred behind the bar" and "the bar
shows vertical lines".

This is arithmetic, not rendering: it needs no screen and no GPU.
"""

import argparse
import sys

# The geometry the effect reports for the Konsole it was measured on (log_geometry in the journal).
FRAME = (1467, 666, 905, 758)          # x, y, w, h -- the frame, which vTexCoord runs across
EXPANDED = (1453, 664, 933, 762)       # the frame plus the decoration's shadow margins
BAR = 38


def region_for(kind, reach):
    fx, fy, fw, fh = FRAME
    if kind == "band":
        return (fx - reach, fy - reach, fw + 2 * reach, BAR + 2 * reach)
    return EXPANDED


def band_v_range():
    """vTexCoord over the band, bottom-up: 1 at the frame's top, 1 - bar/frameHeight at its bottom."""
    return (1.0 - BAR / FRAME[3], 1.0)


def sample(kind, origin, reach):
    """The uv the SHADER computes for the band's top and bottom rows, with `origin` as written.

    `origin="top"`    is `(frame.y - region.y) / region.height`     -- the v axis read downwards.
    `origin="bottom"` is `(region.bottom - frame.bottom) / region.height` -- the v axis read upwards.
    """
    fx, fy, fw, fh = FRAME
    rx, ry, rw, rh = region_for(kind, reach)
    scale = fh / rh
    if origin == "top":
        offset = (fy - ry) / rh
    else:
        offset = ((ry + rh) - (fy + fh)) / rh
    v0, v1 = band_v_range()
    lo, hi = offset + v0 * scale, offset + v1 * scale
    return offset, scale, min(lo, hi), max(lo, hi)


def verdict(kind, origin, reach=44):
    offset, scale, lo, hi = sample(kind, origin, reach)
    inside = 0.0 <= lo and hi <= 1.0
    return {"region": kind, "origin": origin, "offset": offset, "scale": scale,
            "uv_min": lo, "uv_max": hi, "inside": inside}


def self_test():
    """The two cases whose answer is known by the geometry, and the one that hid the bug."""
    problems = []
    bad = verdict("band", "top")
    good = verdict("band", "bottom")
    whole_top = verdict("whole", "top")
    whole_bottom = verdict("whole", "bottom")
    print("  band, top-origin offset    uv %.3f..%.3f  inside=%s" % (bad["uv_min"], bad["uv_max"], bad["inside"]))
    print("  band, bottom-origin offset uv %.3f..%.3f  inside=%s" % (good["uv_min"], good["uv_max"], good["inside"]))
    print("  whole, top-origin offset   uv %.3f..%.3f  inside=%s" % (whole_top["uv_min"], whole_top["uv_max"], whole_top["inside"]))
    print("  whole, bottom-origin offset uv %.3f..%.3f  inside=%s" % (whole_bottom["uv_min"], whole_bottom["uv_max"], whole_bottom["inside"]))
    if bad["inside"]:
        problems.append("the band with the TOP-origin offset was reported INSIDE: this instrument "
                        "cannot see the defect it exists for")
    if not good["inside"]:
        problems.append("the band with the BOTTOM-origin offset is OUTSIDE: the fix is wrong")
    if good["uv_max"] > 0.7:
        problems.append("the band should land in the region's first %.3f of v (the reach above the "
                        "frame), but it reaches %.3f" % (44.0 / 126.0, good["uv_max"]))
    if not whole_top["inside"] or not whole_bottom["inside"]:
        problems.append("both origins agree on the whole geometry -- that is why the wrong one "
                        "survived there, and this instrument must reproduce that")
    if abs(whole_top["uv_max"] - whole_bottom["uv_max"]) > 0.02:
        problems.append("the two origins disagree on the whole geometry by more than the margins: "
                        "the story this instrument tells would be wrong")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true", help="check the known-geometry cases")
    args = parser.parse_args()
    if args.self_test:
        problems = self_test()
        for p in problems:
            print("FAIL: " + p)
        print("self-test: %s" % ("FAILED" if problems else "ok"))
        return 1 if problems else 0
    for kind in ("band", "whole"):
        for origin in ("top", "bottom"):
            v = verdict(kind, origin)
            print("%-6s %-7s offset=%+9.4f scale=%8.4f uv=%+8.3f..%+8.3f inside=%s"
                  % (kind, origin, v["offset"], v["scale"], v["uv_min"], v["uv_max"], v["inside"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())

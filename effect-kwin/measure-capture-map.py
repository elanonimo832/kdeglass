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


def region_for(kind, reach=44):
    fx, fy, fw, fh = FRAME
    if kind == "band":
        return (fx - reach, fy - reach, fw + 2 * reach, BAR + 2 * reach)
    return EXPANDED


def band_v_range():
    """vTexCoord over the band, bottom-up: 1 at the frame's top, 1 - bar/frameHeight at its bottom."""
    return (1.0 - BAR / FRAME[3], 1.0)


def sample(kind, origin, reach=44):
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


def _text_region(rows, cols, seed=5):
    """A 'screen region' with high-contrast text -- the thing a broken mapping turns into lines."""
    import numpy as np
    rng = np.random.default_rng(seed)
    img = np.full((rows, cols, 3), 0.80)
    y = 0
    while y < rows - 8:
        rh = int(rng.integers(6, 10))
        x = 8
        while x < cols - 8:
            w = int(rng.integers(1, 3))
            if rng.random() < 0.62:
                img[y:y + rh, x:x + w] = 0.12
            x += w + int(rng.integers(2, 5))
        y += rh + int(rng.integers(4, 10))
    return img


def render(path):
    """What the band SHOWS, row by row, under the two offsets -- the defect made visible.

    This isolates the MAPPING, not the whole material: for each row of the band it takes the row of
    the region that `offset + v * scale` asks for, clamps it the way a texture does, and averages it
    horizontally -- which is what the frost's taps do along one row. With the top-origin offset every
    band row lands on the same clamped row, so one row is repeated down the band: vertical lines,
    which is what the user photographed. With the bottom-origin offset each row takes the row of the
    backdrop it belongs to, and the band shows the backdrop that is behind it.
    """
    import numpy as np
    from PIL import Image
    rows, cols = 126, 400
    region = _text_region(rows, cols)
    scale = FRAME[3] / rows

    def band_rows(origin):
        offset = sample("band", origin)[0]
        v0, v1 = band_v_range()
        out = []
        for r in range(BAR):
            v = v1 + (v0 - v1) * (r + 0.5) / BAR        # row 0 is the band's TOP, which is v1
            uv = min(1.0, max(0.0, offset + v * scale))  # the texture clamps
            out.append(int(round((1.0 - uv) * (rows - 1))))
        return out

    bug, fix = band_rows("top"), band_rows("bottom")
    print("  the region's row each band row samples (top-origin -> bottom-origin):")
    for r in (0, BAR // 2, BAR - 1):
        print("    band row %2d -> %3d  ->  %3d" % (r, bug[r], fix[r]))

    def band_image(rows_used):
        out = np.zeros((BAR, cols, 3))
        k = 8                                            # the frost's footprint, in region pixels
        for r, src in enumerate(rows_used):
            acc = np.zeros((cols, 3))
            n = 0
            for dy in range(-k, k + 1):
                row = region[min(rows - 1, max(0, src + dy))]    # the texture clamps in BOTH axes
                for dx in range(-k, k + 1):
                    acc += row[np.clip(np.arange(cols) + dx, 0, cols - 1)]
                    n += 1
            out[r] = acc / n
        return out

    panels = np.full((rows + BAR + 8, cols * 2 + 10, 3), 1.0)
    panels[0:rows, 0:cols] = region
    panels[rows + 4:rows + 4 + BAR, 0:cols] = band_image(bug)
    panels[0:rows, cols + 10:] = region
    panels[rows + 4:rows + 4 + BAR, cols + 10:] = band_image(fix)
    img = (np.clip(panels, 0, 1) * 255).astype("uint8")
    Image.fromarray(img).resize(((cols * 2 + 10) * 2, (rows + BAR + 8) * 2), Image.NEAREST).save(path)
    print("  left  panel: the band under the TOP-origin offset -- one clamped row, repeated")
    print("  right panel: the band under the BOTTOM-origin offset -- the backdrop behind it")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true", help="check the known-geometry cases")
    parser.add_argument("--render", metavar="OUT.png", help="draw what each offset makes the band show")
    args = parser.parse_args()
    if args.render:
        return render(args.render)
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

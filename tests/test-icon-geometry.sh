# M5 — the squircle radius of the macOS icons, MEASURED from the real screenshots.
#
# docs/ROADMAP.md: "The squircle radii of the folder icons are missing. There are iOS values in
# the kit, but the macOS ones could not be confirmed. Done when: the folder icons carry the correct
# squircle, OR it is documented that the value is not verifiable."
#
# This file pins what that answer actually is, and it pins it in three parts:
#
#   1. THE INSTRUMENT IS ABLE TO MEASURE. `tools/measure-icon-geometry.py --self-test` draws a
#      corner of a KNOWN radius, reads it back with the same reader it uses on a screenshot, and
#      recovers the radius. Without this, a number from a photo is a coincidence, not a measure.
#   2. THE VALUE HAS A PROVENANCE. The token says which screenshots it came from, on which icons,
#      with which method and on which date. A token is a figure with an origin or it is a rumour.
#   3. THE PART THAT IS **NOT** VERIFIABLE IS DECLARED. One of them, and it is the honest half
#      of M5: at ~96 px with a 1 px edge the CIRCLE and the CONTINUOUS corner are indistinguishable,
#      so the smoothing cannot be confirmed from these captures at all.
#
# AND IT PINS THE CORRECTION OF 2026-10-16. The reader these figures were first taken with was
# PHASE-DEPENDENT: its two errors cancelled at a half-pixel edge -- the only phase its self-test drew
# -- and nowhere else, so a drawn R = 8.0 read 5.30 on an integer edge. The figures moved with it:
# the app icon from 0.215 to 0.250 and the folder from 0.049 to 0.097, while the installed theme
# stayed at 0.075. Two of M5's conclusions therefore changed direction, and the assertions below pin
# the CORRECTED ones, including the one that says the theme is no longer the rounder of the two.
#
# The test does NOT touch `muestras/`: those are the user's screenshots and they are gitignored.
# What is versioned is the measurement, never the pixels it came from.

TOOL="$PROJECT/tools/measure-icon-geometry.py"
TOKEN="$PROJECT/tokens/tokens-icon-geometry.toml"
EVID="$PROJECT/evidence/2026-10-15-m5-icon-corner.png"

afirmar_existe "the icon measuring instrument exists" "$TOOL"
afirmar "the instrument is executable" test -x "$TOOL"

# 1. The instrument can measure: a known radius, drawn and read back.
#
# THE OUTPUT IS CAPTURED ONCE. The self-test draws and fits twelve phase cases on top of the
# radii it already checked; running it once per assertion multiplied the file's runtime by the
# number of assertions, and this file has a per-file time bound in `tests/run.sh`.
SELFTEST_OUT="$(mktemp "${TMPDIR:-/tmp}/icon-self-test.XXXXXX")"
python3 "$TOOL" --self-test > "$SELFTEST_OUT" 2>&1
afirmar_igual "the instrument recovers KNOWN radii from a drawn corner" "0" "$?"

# 1b. AND IT SWEEPS THE SUBPIXEL PHASES. This is the assertion that was missing, and its absence is
# exactly why the phase term went unnoticed (HANDOFF 10o): the old self-test drew every corner with
# its edge on a HALF pixel, which is the one phase where the profile's two errors cancel, so it
# recovered R = 14, 20 and 26 with 0.00 px of error while an INTEGER edge read a drawn R = 8.0 as
# 5.30. A self-test that only visits the phase that agrees with it cannot see the phase it is wrong
# about. Both phases must be named in the output, and the worst error must be bounded.
afirmar_contiene "the self-test sweeps the subpixel PHASES" "$SELFTEST_OUT" 'self-test phase'
afirmar_contiene "the sweep includes the INTEGER edge, where the old reader read 5.30 for R = 8" \
    "$SELFTEST_OUT" 'phase 0\.00'
afirmar_contiene "the sweep includes the HALF-pixel edge, the one that used to cancel" \
    "$SELFTEST_OUT" 'phase 0\.50'
afirmar "the sweep's worst error is inside the bound the token declares" \
    bash -c "grep -qE 'worst phase error [0-4]\\.' '$SELFTEST_OUT'"
rm -f "$SELFTEST_OUT"

# 2. The token, with its provenance.
afirmar_existe "the measured icon geometry token exists" "$TOKEN"
afirmar_contiene "the token declares the squircle radius ratio" "$TOKEN" '^radius_ratio'
afirmar_contiene "the token declares its uncertainty" "$TOKEN" 'uncertainty'
afirmar_contiene "the token names the SCREENSHOTS it was measured from" "$TOKEN" 'muestras/'
afirmar_contiene "the token names the ICONS it was measured on" "$TOKEN" 'Launchpad|Dock'
afirmar_contiene "the token names the method" "$TOKEN" 'measure-icon-geometry'
afirmar_contiene "the token carries a date" "$TOKEN" 'date'

# 2b. THE THREE FIGURES ARE CHECKED AGAINST THE FILE, NOT AGAINST A NUMBER REMEMBERED HERE. Two
# properties, both read out of the token:
#   * each ratio must agree with its own radius and side, so editing one of the three without the
#     other two cannot pass -- which is the failure mode of a token whose value was copied by hand;
#   * each uncertainty must be at least the reader's own bound divided by that figure's side: the
#     instrument's precision is a floor under the token's, and rounding it DOWN is how a measurement
#     claims a precision its method does not have.
afirmar "each ratio agrees with its own radius and side, read from the token" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))["measure"]
bad = []
for sec in ("", "folder", "installed_theme"):
    d = t if not sec else t[sec]
    got = float(d["radius_px"]) / float(d["side_px"])
    if abs(got - float(d["radius_ratio"])) > 0.01:
        bad.append((sec or "app") + ": " + str(got) + " != " + str(d["radius_ratio"]))
sys.exit(0 if not bad else 1)'
afirmar "each uncertainty is the reader's bound, rounded up for its own side" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))["measure"]
bound = float(t["reader_bound_px"])
bad = []
for sec in ("", "folder", "installed_theme"):
    d = t if not sec else t[sec]
    floor = bound / float(d["side_px"])
    if float(d["uncertainty"]) + 1e-9 < floor:
        bad.append((sec or "app") + ": " + str(d["uncertainty"]) + " < " + str(floor))
sys.exit(0 if not bad else 1)'
# ... and the token has to say WHICH reader produced the figures and that it is phase-independent:
# the value is only as good as the instrument that read it, and 10o's instrument was not.
afirmar_contiene "the token names the phase-independent reader that produced the figures" \
    "$TOKEN" 'phase-independent|phase independent'
afirmar_contiene "and it carries that reader's own bound" "$TOKEN" 'reader_bound_px'

# 3. The honest half: what is NOT verifiable is declared, and it cannot quietly become a claim.
afirmar_contiene "the token declares that the corner FAMILY is not resolvable" "$TOKEN" 'familia|smoothing|continua'

# 3b. THE FOLDER -- which is the question M5 literally asks. It used to be declared NOT VERIFIABLE,
# because none of the captures showed one. `muestras/Untitled6.png` does (a Finder window with four),
# so now it is a MEASUREMENT, and the test demands the measurement instead of the excuse. These
# assertions were written BEFORE the token had the section and were watched fail: with the excuse
# still in place the numbers would be pinned nowhere.
afirmar_contiene "the token carries the FOLDER measurement" "$TOKEN" '^\[measure\.folder\]'
afirmar_contiene "the folder measurement names the capture it came from" "$TOKEN" 'Untitled6'
afirmar_contiene "the folder measurement says WHICH corner it read, and why" "$TOKEN" 'top-right'
afirmar_contiene "the folder measurement declares the rows it fitted" "$TOKEN" 'rows_fitted'
afirmar "the folder ratio is inside the range its measurement supports" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
r = float(t["measure"]["folder"]["radius_ratio"])
sys.exit(0 if 0.05 <= r <= 0.15 else 1)'
# AND IT IS NOT THE APP ICON'S SQUIRCLE -- but the corrected reader also says it is NOT the ">4x
# tighter" the first reader reported. The phase bias inflated that ratio, so the test pins a BAND and
# not a floor: a floor of 3 would pin the bias itself and fail the moment the reader got honest.
afirmar "the folder is tighter than the app icon, but by less than the biased reader claimed" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
app = float(t["measure"]["radius_ratio"]); folder = float(t["measure"]["folder"]["radius_ratio"])
sys.exit(0 if 2.0 <= app / folder <= 3.5 else 1)'

# 3c. THE THEME THE USER ALREADY RUNS. M5 left an ERRAND: the measured macOS radius cannot be applied
# because the global theme points at Breeze, and an icon theme is not a milestone of this ROADMAP. The
# user's desktop already draws its folders with `MacTahoe-light`, so the question became whether that
# theme CARRIES the geometry -- if it did, there would be nothing to apply. It does not, and the gap
# is what makes the errand actionable. These assertions were written BEFORE the token had the section
# and were watched fail: without the section the file read as "the value was measured and that is all".
afirmar_contiene "the token carries the INSTALLED theme's measurement" "$TOKEN" '^\[measure\.installed_theme\]'
afirmar_contiene "it names the third-party theme it read" "$TOKEN" 'MacTahoe'
afirmar_contiene "it names the SVG the desktop's folders are drawn from" "$TOKEN" 'places/scalable/folder\.svg'
# It is read IN PLACE. This repository does not version another author's artwork, exactly as it does
# not version the user's screenshots: what travels is the number.
afirmar_contiene "and reads it IN PLACE, never from a copy in this repository" "$TOKEN" '\.local/share/icons'
afirmar "the installed theme's ratio is inside the range its method supports" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
r = float(t["measure"]["installed_theme"]["radius_ratio"])
sys.exit(0 if 0.05 <= r <= 0.10 else 1)'
# THE VERDICT, as a property and not as a sentence, AND THE CORRECTED READER REVERSED IT. The first
# reader had the installed theme 1.5x ROUNDER than macOS and outside its window on the high side; with
# the phase bias removed the macOS folder is the wider one. What must not evaporate is the
# DISAGREEMENT itself: the theme's corner must still sit off the macOS figure, now on the LOW side. A
# later edit that quietly restores "the theme is rounder" fails here.
afirmar "the installed theme's corner still sits OFF the corrected macOS figure, on the low side" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
inst = float(t["measure"]["installed_theme"]["radius_ratio"])
mac = float(t["measure"]["folder"]["radius_ratio"])
sys.exit(0 if inst < mac else 1)'
# ... and the token has to SAY that the first verdict was reversed, so a reader of the file cannot
# come away with the old "1.5x rounder" story.
afirmar_contiene "and the token records that the earlier verdict was reversed" "$TOKEN" 'REVERS'
# AND THE RASTER'S OWN TRAP IS KEPT VISIBLE. The literal 120 px read is the coarse one and it is kept
# as a SEPARATE key with the 10x read beside it; a later edit cannot quietly promote one of them to
# the value. With a true subpixel edge the 120 px read is ~5% HIGH (it used to be 12% low, because a
# biased crossing on an integer reference edge is what "low" was), so the property is AGREEMENT
# within the token's own window, not a direction.
afirmar_contiene "the token keeps the literal 120 px raster read apart" "$TOKEN" 'radius_ratio_at_120'
afirmar_contiene "and the 10x raster read beside it" "$TOKEN" 'radius_ratio_at_10x'
afirmar "both raster reads agree with the value inside the token's own window" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
g = t["measure"]["installed_theme"]
u = float(g["uncertainty"]); v = float(g["radius_ratio"])
sys.exit(0 if abs(float(g["radius_ratio_at_120"]) - v) <= u
            and abs(float(g["radius_ratio_at_10x"]) - v) <= u else 1)'

# The value is in the range the measurement supports. This is a WINDOW on purpose: a token that
# claimed a single confident number at 1 px resolution would be lying about its own precision.
afirmar "the measured ratio is inside the range the captures support" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
r = float(t["measure"]["radius_ratio"])
sys.exit(0 if 0.15 <= r <= 0.30 else 1)'

# The evidence is OUR drawing of the measured geometry, never a crop of Apple's pixels.
afirmar_existe "the evidence drawing exists" "$EVID"
afirmar "the evidence is our own drawing, not a screenshot" python3 -c '
import sys
from PIL import Image
im = Image.open("'"$EVID"'")
sys.exit(0 if im.size[0] > 200 and im.size[1] > 100 else 1)'

# ... and the same for the FOLDER, which is a second measurement and needs its own drawing: an
# evidence file for the app figure is not evidence for the folder.
EVID_FOLDER="$PROJECT/evidence/2026-10-15-m5-folder-corner.png"
afirmar_existe "the folder evidence drawing exists" "$EVID_FOLDER"
afirmar "the folder evidence is our own drawing, not a screenshot" python3 -c '
import sys
from PIL import Image
im = Image.open("'"$EVID_FOLDER"'")
sys.exit(0 if im.size[0] > 200 and im.size[1] > 100 else 1)'

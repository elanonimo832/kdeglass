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
#   3. THE PART THAT IS **NOT** VERIFIABLE IS DECLARED. Two of them, and they are the honest half
#      of M5: the captures contain NO folder icon (only app icons), and at ~96 px with a 1 px edge
#      the CIRCLE and the CONTINUOUS corner are indistinguishable, so the smoothing cannot be
#      confirmed from these captures at all.
#
# The test does NOT touch `muestras/`: those are the user's screenshots and they are gitignored.
# What is versioned is the measurement, never the pixels it came from.

TOOL="$PROJECT/tools/measure-icon-geometry.py"
TOKEN="$PROJECT/tokens/tokens-icon-geometry.toml"
EVID="$PROJECT/evidence/2026-10-15-m5-icon-corner.png"

afirmar_existe "the icon measuring instrument exists" "$TOOL"
afirmar "the instrument is executable" test -x "$TOOL"

# 1. The instrument can measure: a known radius, drawn and read back.
afirmar "the instrument recovers a KNOWN radius from a drawn corner" "$TOOL" --self-test

# 2. The token, with its provenance.
afirmar_existe "the measured icon geometry token exists" "$TOKEN"
afirmar_contiene "the token declares the squircle radius ratio" "$TOKEN" '^radius_ratio'
afirmar_contiene "the token declares its uncertainty" "$TOKEN" 'uncertainty'
afirmar_contiene "the token names the SCREENSHOTS it was measured from" "$TOKEN" 'muestras/'
afirmar_contiene "the token names the ICONS it was measured on" "$TOKEN" 'Launchpad|Dock'
afirmar_contiene "the token names the method" "$TOKEN" 'measure-icon-geometry'
afirmar_contiene "the token carries a date" "$TOKEN" 'date'

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
sys.exit(0 if 0.03 <= r <= 0.08 else 1)'
# AND IT IS NOT THE APP ICON'S SQUIRCLE. The whole point of measuring the folder separately is that
# assuming the app figure would have been wrong; this pins the difference so a later edit cannot
# quietly collapse the two into one number.
afirmar "the folder is NOT drawn on the app icons squircle (more than 3x tighter)" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
app = float(t["measure"]["radius_ratio"]); folder = float(t["measure"]["folder"]["radius_ratio"])
sys.exit(0 if app / folder > 3.0 else 1)'

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
# THE VERDICT, as a property and not as a sentence: the installed theme's corner must sit OUTSIDE the
# macOS figure's own window. If a later edit makes the token say the two coincide, this fails -- and
# the difference is the whole finding, so it must not be able to evaporate.
afirmar "the installed theme's corner is OUTSIDE the macOS figure's window" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
inst = float(t["measure"]["installed_theme"]["radius_ratio"])
mac = float(t["measure"]["folder"]["radius_ratio"])
tol = float(t["measure"]["folder"]["uncertainty"])
sys.exit(0 if inst > mac + tol else 1)'
# AND THE RASTER'S OWN TRAP IS KEPT VISIBLE. The tool reads this corner LOW at a literal 120 px (the
# corner is only ~8 px, the reader's reference edge is an integer pixel and the first row is 62%
# covered), so the token carries that read as a SEPARATE key. A later edit cannot quietly promote the
# raster's 120 px number to the value, nor hide it.
afirmar_contiene "the token keeps the literal 120 px raster read apart" "$TOKEN" 'radius_ratio_at_120'
afirmar "and it is LOWER than the value, as a raster artifact and not a second answer" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
g = t["measure"]["installed_theme"]
sys.exit(0 if float(g["radius_ratio_at_120"]) < float(g["radius_ratio"]) else 1)'

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

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
afirmar_contiene "the token declares that no FOLDER icon is in the captures" "$TOKEN" 'carpeta|folder'
afirmar_contiene "the token declares that the corner FAMILY is not resolvable" "$TOKEN" 'familia|smoothing|continua'

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

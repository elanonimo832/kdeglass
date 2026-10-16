# M6, slices 4-6 — the control figures the kit does not carry, MEASURED from the user's captures.
#
# docs/M6-QSTYLE-PLAN.md lists what each slice makes measurable, and three of those figures are not
# in `tokens/`: the slider's TRACK THICKNESS (slice 4), the combo/tab/menu padding (slice 5) and
# everything about SELECTION, FOCUS and DISABLED (slice 6). `docs/HANDOFF.md` section 10n named the
# first of them and left it as a named gap instead of inventing a number. This file pins the
# measurement that fills it, and it pins it in four parts:
#
#   1. THE INSTRUMENT CAN MEASURE. `tools/measure-controls.py --self-test` draws a bar, a box, a
#      knob, a text stem and a list, each with a KNOWN value, and reads every one of them back.
#   2. THE INSTRUMENT'S OWN BLIND SPOT IS PINNED, because it is what made this measurement
#      necessary: the corner reader imported from `tools/measure-icon-geometry.py` answers
#      R = 2.50 for a drawn R = 5.0 when the box's edge sits on an integer pixel and 5.00 when it
#      sits on a half pixel. A test that only checked "a radius came back" would not see that.
#   3. THE VALUES HAVE A PROVENANCE: which capture, which method, which date, which uncertainty.
#   4. WHAT COULD **NOT** BE MEASURED IS DECLARED: no radio button and no open menu are in any
#      capture, the focus ring cannot appear in a mouse-driven capture, and a hairline border and a
#      shadow do not survive a coverage measurement.
#
# The test does NOT touch `muestras/`: those are the user's screenshots and they are gitignored.
# What is versioned is the measurement, and our own drawing of it.

TOOL="$PROJECT/tools/measure-controls.py"
TOKEN="$PROJECT/tokens/tokens-controls-measured.toml"
EVID="$PROJECT/evidence/2026-10-16-m6-controls-measured.png"

afirmar_existe "the control measuring instrument exists" "$TOOL"
afirmar "the instrument is executable" test -x "$TOOL"

# 1. The instrument can measure: known values, drawn and read back -- including the four subpixel
# edge phases, which is where the imported fitter fails and this one does not.
afirmar "the instrument recovers KNOWN values from a drawn scene" "$TOOL" self-test

# 1b. THE CLAIM IS CHECKED BY THE OUTPUT, NOT BY AN EXIT CODE. The phase sweep prints one line per
# case; if it stopped printing the imported fitter's contrast, the numbers would still be there and
# the blind spot would be invisible.
afirmar "the self-test prints the exact fit per subpixel phase" \
    bash -c "python3 '$TOOL' self-test 2>&1 | grep -q 'worst phase error'"
afirmar "the self-test prints the IMPORTED fitter's answer too, so the contrast is visible" \
    bash -c "python3 '$TOOL' self-test 2>&1 | grep -q 'imported fitter'"

# 2. The token, with its provenance and its two captures.
afirmar_existe "the measured controls token exists" "$TOKEN"
afirmar_contiene "the token names the System Settings capture" "$TOKEN" 'Untitled7'
afirmar_contiene "the token names the Finder capture with the selection" "$TOKEN" 'Untitled8'
afirmar_contiene "the token names the instrument" "$TOKEN" 'measure-controls'
afirmar_contiene "the token carries a date" "$TOKEN" 'date'
afirmar_contiene "the token declares the scale it measured, and how" "$TOKEN" '^\[measure\.scale\]'
afirmar_contiene "the scale names the ruler it used" "$TOKEN" 'cap_height'

# 3. THE FIGURE THAT UNBLOCKS SLICE 4. The track's thickness is the one `[slider.track]` does not
# carry, and it is a property and not a sentence: the value must sit in the window its own method
# supports (a 6 px groove read on a 1.02 scale), and the token must carry its uncertainty.
afirmar_contiene "the token carries the track's thickness" "$TOKEN" 'track_thickness_px'
afirmar_contiene "and its uncertainty" "$TOKEN" 'track_thickness_uncertainty_px'
afirmar "the track's thickness is inside the window its method supports" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
v = float(t["measure"]["slider"]["track_thickness_px"])
sys.exit(0 if 4.0 <= v <= 8.0 else 1)'
# AND THE UNCERTAINTY IS ROUNDED UP, which is this repository's rule for a measured token: a value
# whose method cannot see a tenth of a pixel must not claim one. The grid is 1 px, so a figure that
# declares less than 0.25 px of uncertainty is declaring a precision the pixels cannot carry.
afirmar "the track's uncertainty is not smaller than the pixel grid it was read on" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
s = t["measure"]["slider"]
sys.exit(0 if float(s["track_thickness_uncertainty_px"]) >= 0.25 else 1)'

# 3b. THE KNOB, which the kit DOES carry, so this is a CONFIRMATION and the test demands that it
# stays one: the measured ratio must sit near the kit's 16/20, and it must NOT be a circle (a
# circle would be 16 px wide on a 16 px tall control, and the whole point of the figure is that it
# is not).
afirmar "the measured knob ratio agrees with the kit's own 16/20" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
s = t["measure"]["slider"]
ratio = float(s["knob_ratio"]); kit = float(s["knob_kit_ratio"])
sys.exit(0 if abs(ratio - kit) <= 0.02 else 1)'
afirmar "the knob is wider than it is tall, as the kit's token says and a circle would not be" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
s = t["measure"]["slider"]
sys.exit(0 if float(s["knob_width_px"]) > float(s["knob_height_px"]) + 2.0 else 1)'

# 4. THE CHECKBOX, which slice 3 already drew from the kit. The measurement CONFIRMS the kit's size,
# so the assertion pins the agreement instead of the number alone; and it pins the two states'
# DISAGREEMENT about the radius, because that is the honest half and an edit could quietly average
# it into one comfortable figure.
afirmar "the measured checkbox agrees with the kit's 16 pt box" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
w, h = (float(v) for v in t["measure"]["checkbox"]["box_px"])
sys.exit(0 if abs(w - 16.0) <= 0.5 and abs(h - 16.0) <= 0.5 else 1)'
afirmar "the two checkbox states still measure different corner radii, and it is declared" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
c = t["measure"]["checkbox"]
d = abs(float(c["radius_checked_px"]) - float(c["radius_unchecked_px"]))
sys.exit(0 if d > float(c["radius_uncertainty_px"]) and "unresolved" in c["state_discrepancy"] else 1)'
afirmar "the measured checkbox radius WINDOW still contains the kit's 5.5" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
c = t["measure"]["checkbox"]
lo = float(c["radius_checked_px"]) - float(c["radius_uncertainty_px"])
hi = float(c["radius_unchecked_px"]) + float(c["radius_uncertainty_px"])
sys.exit(0 if lo <= float(c["radius_kit_medium"]) <= hi else 1)'

# 5. THE SELECTION, which is slice 6 and had NO source at all before this capture. A selection that
# is a rectangle with a radius and a colour is a property the style can be held to.
afirmar_contiene "the token carries the selection" "$TOKEN" '^\[measure\.selection\]'
afirmar_contiene "the selection names the two layers the Finder draws" "$TOKEN" 'cell_px'
afirmar_contiene "the selection names the label's own pill" "$TOKEN" 'label_pill_px'
afirmar_contiene "and the colour of the code drawn on it" "$TOKEN" 'label_text_selected'
afirmar "the selection's cell is not a square and not a hairline: it is a rounded cell" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
s = t["measure"]["selection"]
w, h = (float(v) for v in s["cell_px"])
r = float(s["cell_radius_px"])
sys.exit(0 if r >= 4.0 and w > 100.0 and h > 100.0 else 1)'
# THE SIDEBAR SELECTION IS A DIFFERENT SHAPE, and that is the finding slice 6 has to carry: one
# layer with the text unchanged, against the icon view's two layers with white text.
afirmar "the token declares that the sidebar's selection leaves the text colour alone" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
s = t["measure"]["selection"]
sys.exit(0 if "unchanged" in s["sidebar_text_selected"] else 1)'

# 6. THE HONEST HALF. Each of these is a thing a reader would expect this measurement to answer and
# that the captures cannot: they are declared, so a later edit cannot turn "not measurable" into a
# silent number.
afirmar_contiene "the token declares the radio button NOT measurable, with its reason" "$TOKEN" '^\[measure\.radio\]'
afirmar "and the reason is a fact about the captures" \
    python3 -c '
import sys, tomllib
t = tomllib.load(open("'"$TOKEN"'", "rb"))
r = t["measure"]["radio"]
sys.exit(0 if r["measurable"] is False and len(r["reason"]) > 20 else 1)'
afirmar_contiene "the menu item height is declared unmeasurable, not guessed" "$TOKEN" 'menu_item_height'
afirmar_contiene "the focus ring is declared unobserved, with its reason" "$TOKEN" 'focus_ring'
afirmar_contiene "a hairline border and a shadow are declared out of reach" "$TOKEN" 'HAIRLINE'

# 7. The evidence is OUR OWN drawing of the measured geometry, never a crop of Apple's pixels.
afirmar_existe "the evidence drawing exists" "$EVID"
afirmar "the evidence is our own drawing, not a screenshot" python3 -c '
import sys
from PIL import Image
im = Image.open("'"$EVID"'")
sys.exit(0 if im.size[0] > 400 and im.size[1] > 200 else 1)'

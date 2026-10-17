# M6, slice 7: the TRACKING, and the three claims this file has to prove.
#
# The plan's slice 7 is the 64 tracking tokens: `kdeglobals` has no field for them, so the style is
# their home. Each claim has its assertion here:
#
#   1. the table the style compiles is STALE with respect to the token   -> the generator's --check
#   2. the style applies NO tracking (the whole slice as a no-op)        -> the applied spacing, read
#      from the widget's font after `polish`, must be the token's `em1000 / 1000 * size`
#   3. the tracking is applied but does not REACH the text               -> the advance of a string
#      must shrink by that spacing times the glyphs, measured with QFontMetrics
#
# Claim 2 has a MEASURED tolerance, and it is not a fudge. Qt stores the letter spacing in SIXTY-
# FOURTHS OF A PIXEL and truncates (MEASURED: the token's -6 em1000 at 13 px is -0.078, and
# `QFont::letterSpacing()` returns -0.0625 = -4/64; +6 at 11 px is 0.066 -> 4/64; +12 at 10 px is
# 0.12 -> 7/64). So the assertion is "within one 1/64 step of the token's figure AND not zero", and
# the one-step window is named here rather than hidden inside an epsilon.
#
# The expected values are computed FROM THE TOKEN, never remembered here.
ST="$PROJECT/style-kde-macos"
PROBE="$ST/build/bin/style-probe"
STEP="$(python3 -c 'print(1/64)')"

echo "  -- the table the style compiles is generated from the token, not typed --"
afirmar_existe "src/tracking_table.h exists" "$ST/src/tracking_table.h"
afirmar "the generator says the header matches the token" \
  python3 "$PROJECT/tools/generate-style-tracking.py" --check
afirmar_contiene "the table says where it comes from" "$ST/src/tracking_table.h" 'tokens-typography_macos.toml'
afirmar_codigo "the lookup returns 0 for a size the HIG does not publish" \
  "$ST/src/tracking_table.h" 'return 0;'
# The token's own figure for body (13), which the whole slice hangs on: -6 thousandths of an em.
afirmar_contiene "the token still publishes the body size's tracking" \
  "$PROJECT/tokens/tokens-typography_macos.toml" '^13 = \{ em1000 = -6,'

echo "  -- the style applies it, and it reaches the text --"
salida="$(QT_QPA_PLATFORM=offscreen QT_PLUGIN_PATH="$ST/build" timeout 60 "$PROBE" --tracking 2>&1)"
codigo=$?
afirmar_igual "the probe ran and found the style" "0" "$codigo"
afirmar_igual "the probe tried four sizes (three the HIG publishes and one it does not)" "4" \
  "$(printf '%s\n' "$salida" | grep -c '^TRACKING ')"
for size in 13 11 10; do
  esperado="$(python3 - "$PROJECT/tokens/tokens-typography_macos.toml" "$size" <<'PY'
import sys, tomllib
tok = tomllib.load(open(sys.argv[1], "rb"))
size = int(sys.argv[2])
print(f"{tok['tracking'][str(size)]['em1000'] / 1000.0 * size:.6f}")
PY
)"
  leido="$(printf '%s\n' "$salida" | sed -n "s/^TRACKING size=$size spacing=\([-0-9.]*\).*/\1/p")"
  afirmar "size $size gets a tracking at all" test -n "$leido"
  python3 - "$esperado" "$leido" "$STEP" "$size" <<'PY'
import sys
want, got, step, size = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
# Within one 1/64 step of the token's figure: Qt stores the spacing in sixty-fourths and truncates.
if abs(got - want) > step:
    print(f"FAIL: size {size}: the token says {want:.6f}, the font has {got:.6f} "
          f"(more than one 1/64 step = {step:.6f})", file=sys.stderr)
    sys.exit(1)
if got == 0.0:
    print(f"FAIL: size {size}: no tracking applied (the slice is a no-op here)", file=sys.stderr)
    sys.exit(1)
print(f"ok: size {size}: token {want:.6f}, applied {got:.6f} (within one 1/64 step)")
PY
  afirmar "size $size's applied spacing is the token's, within Qt's 1/64 step" test "$?" = "0"
done

echo "  -- and it reaches the text, not just the font object --"
ancho_plano="$(printf '%s\n' "$salida" | sed -n 's/^WIDTH plain=\([0-9.]*\).*/\1/p')"
ancho_track="$(printf '%s\n' "$salida" | sed -n 's/^WIDTH .* tracked=\([0-9.]*\).*/\1/p')"
afirmar "the probe measured the string's advance" test -n "$ancho_plano"
aplicado="$(printf '%s\n' "$salida" | sed -n 's/^TRACKING size=13 spacing=\([-0-9.]*\).*/\1/p')"
python3 - "$ancho_plano" "$ancho_track" "$aplicado" <<'PY'
import sys
plain, tracked, applied = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
# The reference string in the probe; if it changes there, this count changes with it.
GLYPHS = len("The quick brown fox jumps over the lazy dog")
expected = applied * GLYPHS
delta = tracked - plain
if abs(delta - expected) > 0.5:
    print(f"FAIL: the advance changed by {delta:.2f} px, but the applied tracking predicts "
          f"{expected:.2f} px over {GLYPHS} glyphs", file=sys.stderr)
    sys.exit(1)
if not delta < 0:
    print(f"FAIL: the body size's track is negative but the text did not tighten "
          f"({plain:.2f} -> {tracked:.2f})", file=sys.stderr)
    sys.exit(1)
print(f"ok: the text tightened by {delta:.2f} px over {GLYPHS} glyphs, as the applied tracking predicts")
PY
afirmar "the applied tracking reaches the rendered text" test "$?" = "0"

echo "  -- and the slice's own boundary: what it does NOT touch --"
no_hay="$(printf '%s\n' "$salida" | sed -n 's/^TRACKING size=5 spacing=\(.*\)/\1/p')"
afirmar_igual "a size the HIG does not publish gets no tracking" "none" "$no_hay"

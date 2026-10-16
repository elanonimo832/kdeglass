# M4 — the macOS type scale, applied to KDE's OWN font roles.
#
# docs/ROADMAP.md: "KDE's text metrics use the macOS scale and there is a comparison of rendered
# text in evidence/". This file checks the three things that decide whether that is true:
#
#   1. THE FONTS REACH kdeglobals THROUGH THE GLOBAL THEME. There is no second package: M3 already
#      ships `contents/defaults`, and M4 adds the font keys to the block that is already there.
#   2. THE SIZE IS macOS's, IN POINTS DERIVED FROM THE PIXEL TOKEN. macOS draws its styles at
#      1 pt = 1 px, so 13 px is the size to reproduce; kdeglobals takes POINTS, and at this machine's
#      font DPI -- 96, with no `forceFontDPI` key: measured -- a point is 96/72 px, so the factor is
#      72/96 = 0.75 and 13 px becomes 9.75 pt. THE PIXEL FIELD WAS THE FIRST ATTEMPT AND IT IS WRONG
#      in a way only a real application shows: `QFont` holds points OR pixels, never both, so
#      `pointSize()` is -1 and any code that re-applies it prints
#          QFont::setPointSize: Point size <= 0 (-1), must be greater than 0
#      Measured in Dolphin, and measured WITH `QT_STYLE_OVERRIDE=Breeze` as well -- so it was the
#      font and not the QStyle. tools/font-probe.cpp is the instrument that settles it, and it is
#      run below: the emitted strings must give `pointSizeF() > 0` AND the same metrics as the
#      pixel-sized reference, or the change moved the render.
#   3. THE WEIGHT IS IN THE LEGACY 0..99 SCALE. This is the trap, and it was measured:
#          fromString("...75...")  -> 700 (Bold)     <- what this repository writes
#          fromString("...400...") -> 900 (Black)    <- what a modern Qt weight produces
#      Anything >= 99 saturates at 900. So writing Qt 6's own `toString()` output (400 for Normal)
#      into kdeglobals paints the text BLACK. The measured table is 0->100, 12->200, 25->300,
#      50->400, 57->500, 63->600, 75->700, 81->800, 87->900.
#
# WHAT KDE CANNOT DO, and this file pins the declaration so it cannot quietly become a claim:
#   * TRACKING. kdeglobals has no letter-spacing key. 64 of the 80 tokens are tracking values, and
#     they have NO destination here. Applying them needs QSS/widget-level styling (M6).
#   * 7 of the 11 styles have no KDE role (large_title, title_1..3, callout, footnote, caption_1):
#     kdeglobals has about seven font keys and they do not map one-to-one onto the HIG's styles.
#   * 4 of the 5 base sizes are iOS/tvOS/visionOS/watchOS, which this project does not target.

LNF="$PROJECT/output/look-and-feel/KdeMacOS"
DEF="$LNF/contents/defaults"
TOKENS="$PROJECT/tokens/tokens-typography_macos.toml"
GEN="$PROJECT/tools/generate-global-theme.py"
EVID="$PROJECT/evidence"

# `contents/defaults` is KDE's [file][group] format, which no INI reader here parses (same helper
# as test-global-theme.sh: one reader, and the assertion reads the REAL file, not a comment).
ini_get() {
  python3 -c '
import re,sys
sec,grp,key=sys.argv[2],sys.argv[3],sys.argv[4]
cur=None
for line in open(sys.argv[1],encoding="utf-8"):
    line=line.strip()
    m=re.match(r"^\[([^\]]+)\](?:\[([^\]]+)\])?$",line)
    if m:
        cur=(m.group(1),m.group(2)); continue
    if cur==(sec,grp) and line.startswith(key+"="):
        print(line.split("=",1)[1]); break
' "$1" "$2" "$3" "$4" 2>/dev/null
}

# A kdeglobals font string is `family,pointSize,pixelSize,styleHint,weight,...`. The repo reads the
# FIELDS, never the whole string: a substring assertion here would pass on a file that also carries
# the wrong weight, which is exactly the bug this milestone is about.
campo_fuente() { # campo_fuente <font-string> <1-based field>
  python3 -c 'import sys; f=sys.argv[1].split(","); print(f[int(sys.argv[2])-1] if len(f)>=int(sys.argv[2]) else "")' "$1" "$2" 2>/dev/null
}

# The token the generator must have read. This is a CROSS-CHECK against the TOML, not a restatement:
# if the token changes and the generated file does not, this fails.
token_de() { # token_de <style> <field>
  python3 -c '
import tomllib,sys
d=tomllib.load(open(sys.argv[1],"rb"))["estilos"][sys.argv[2]]
print(d[sys.argv[3]])
' "$TOKENS" "$1" "$2" 2>/dev/null
}

# macOS's token is in PIXELS and kdeglobals takes POINTS. The factor is the measured font DPI:
# 72/96 = 0.75 (96, no `forceFontDPI`). Derived here so the test cannot agree with a stale constant
# in the generator: if one moves without the other, this fails.
puntos_de() { # puntos_de <pixel size> -> the point size it must become
  python3 -c 'import sys; print(f"{float(sys.argv[1])*0.75:g}")' "$1" 2>/dev/null
}

echo "  -- the generator runs with no argument (the trap M3 found: an empty dry run cannot fail) --"
if python3 "$GEN" >/dev/null 2>&1; then
  ok "generate-global-theme.py exits 0 with no arguments"
else
  fallo "generate-global-theme.py does NOT run with no arguments (its reproducibility check would be a no-op)"
fi

echo "  -- the fonts reach kdeglobals through the global theme --"
afirmar_existe "the global theme's defaults exist" "$DEF"
for k in font menuFont toolBarFont smallestReadableFont fixed; do
  v="$(ini_get "$DEF" kdeglobals General "$k")"
  if [ -n "$v" ]; then ok "[kdeglobals][General] $k is set"; else fallo "[kdeglobals][General] $k is MISSING: KDE would keep its own default"; fi
done
for k in activeFont inactiveFont; do
  v="$(ini_get "$DEF" kdeglobals WM "$k")"
  if [ -n "$v" ]; then ok "[kdeglobals][WM] $k is set (the window title)"; else fallo "[kdeglobals][WM] $k is MISSING"; fi
done

echo "  -- the SIZE is macOS's, in POINTS: the pixel token times 72/96 (the measured font DPI) --"
for par in "General:font:body" "General:menuFont:body" "General:toolBarFont:subheadline" \
           "General:smallestReadableFont:caption_2" "WM:activeFont:headline" "WM:inactiveFont:body"; do
  grp="${par%%:*}"; resto="${par#*:}"; key="${resto%%:*}"; estilo="${resto##*:}"
  v="$(ini_get "$DEF" kdeglobals "$grp" "$key")"
  quiero="$(puntos_de "$(token_de "$estilo" tamano)")"
  punto="$(campo_fuente "$v" 2)"
  pixel="$(campo_fuente "$v" 3)"
  afirmar_igual "[$grp] $key: pointSize = the token '$estilo' size in points (px*72/96)" "$quiero" "$punto"
  afirmar_igual "[$grp] $key: pixelSize must be UNSET (-1), or the point size is not what is in use" "-1" "$pixel"
done

echo "  -- the WEIGHT is in the legacy 0..99 scale (400 in kdeglobals is BLACK, measured) --"
# The mapping this milestone writes, measured against Qt 6.12: CSS -> legacy.
peso_legacy() { case "$1" in 400) echo 50;; 500) echo 57;; 600) echo 63;; 700) echo 75;; 800) echo 81;; *) echo "?";; esac; }
for par in "General:font:body" "General:menuFont:body" "General:toolBarFont:subheadline" \
           "General:smallestReadableFont:caption_2" "WM:activeFont:headline" "WM:inactiveFont:body"; do
  grp="${par%%:*}"; resto="${par#*:}"; key="${resto%%:*}"; estilo="${resto##*:}"
  v="$(ini_get "$DEF" kdeglobals "$grp" "$key")"
  quiero="$(peso_legacy "$(token_de "$estilo" peso)")"
  tengo="$(campo_fuente "$v" 5)"
  afirmar_igual "[$grp] $key: weight is the legacy code for the token '$estilo' weight" "$quiero" "$tengo"
done
# THE TRAP, named: nothing in the emitted fonts may carry a modern Qt/CSS weight, because
# QFont::fromString reads 400 as 900. A `< 100` assertion is what forbids it.
if grep -E '^(font|menuFont|toolBarFont|smallestReadableFont|fixed|activeFont|inactiveFont)=[^#]*,[0-9]{3,},' "$DEF" >/dev/null 2>&1; then
  fallo "a font carries a MODERN weight (>=100): QFont::fromString reads 400 as 900 (Black)"
else
  ok "no font carries a modern Qt weight: every weight is in the legacy 0..99 scale"
fi

echo "  -- the POINT SIZE is REAL, and the RENDER did not move: a Qt 6 probe builds each font --"
# tools/font-probe.cpp prints a REFERENCE (the token's pixel size, same family: the yardstick) and
# then what Qt sees in each emitted string. Three claims, and the third is what lets this file fail:
#   1. pointSizeF() > 0  -- nothing can be handed a -1, which is the message the user saw.
#   2. the metrics EQUAL the reference -- turning px into pt did not move the render.
#   3. the OLD pixel form gives a -1, so the assertion above can actually fail.
PROBE_DIR="$(mktemp -d)"
PROBE="$PROBE_DIR/font-probe"
if g++ -fPIC -std=c++17 $(pkg-config --cflags Qt6Gui) "$PROJECT/tools/font-probe.cpp" \
       -o "$PROBE" $(pkg-config --libs Qt6Gui) 2>/dev/null; then
  ok "font-probe.cpp compiles against this machine's Qt 6"
  for par in "General:font:body" "General:menuFont:body" "General:toolBarFont:subheadline" \
             "General:smallestReadableFont:caption_2" "WM:activeFont:headline" "WM:inactiveFont:body"; do
    grp="${par%%:*}"; resto="${par#*:}"; key="${resto%%:*}"; estilo="${resto##*:}"
    v="$(ini_get "$DEF" kdeglobals "$grp" "$key")"
    # THE YARDSTICK, per role: the very same font with the size in the PIXEL field -- which is the
    # token's unit and what M4 wrote before. Same family, same weight, ONLY the unit changes, so a
    # bold title or an 11 px toolbar font is compared against itself and not against a 13 px body.
    yardstick="$(campo_fuente "$v" 1),-1,$(token_de "$estilo" tamano),5,$(campo_fuente "$v" 5),0,0,0,0,0"
    salida="$(QT_QPA_PLATFORM=offscreen "$PROBE" --reference "$yardstick" "$v" 2>/dev/null)"
    ref_alto="$(printf '%s' "$salida" | sed -n 's/^REFERENCE .*height=\([0-9]*\).*/\1/p')"
    ref_adv="$(printf '%s' "$salida" | sed -n 's/^REFERENCE .*advance=\([0-9]*\).*/\1/p')"
    salida="$(printf '%s' "$salida" | grep '^FONT ')"
    pf="$(printf '%s' "$salida" | sed -n 's/.*pointSizeF=\([-0-9.]*\).*/\1/p')"
    alto="$(printf '%s' "$salida" | sed -n 's/.*height=\([0-9]*\).*/\1/p')"
    adv="$(printf '%s' "$salida" | sed -n 's/.*advance=\([0-9]*\).*/\1/p')"
    if python3 -c "import sys; sys.exit(0 if float('$pf') > 0 else 1)" 2>/dev/null; then
      ok "[$grp] $key: Qt reads pointSizeF=$pf (> 0: it can never be handed a -1)"
    else
      fallo "[$grp] $key: Qt reads pointSizeF=$pf -- a -1 is what prints 'Point size <= 0'"
    fi
    afirmar_igual "[$grp] $key: the render's height equals the pixel-form yardstick's" "$ref_alto" "$alto"
    afirmar_igual "[$grp] $key: the render's advance equals the pixel-form yardstick's" "$ref_adv" "$adv"
  done
  # BREAK-ON-PURPOSE, and it must not pass on an empty reading: the pixel form, parsed as a font,
  # has to give a -1 -- that is what printed the message and it is what the assertions above catch.
  VIEJO_STR="$(campo_fuente "$(ini_get "$DEF" kdeglobals General font)" 1),-1,13,5,50,0,0,0,0,0"
  VIEJO="$(QT_QPA_PLATFORM=offscreen "$PROBE" --reference "$VIEJO_STR" "$VIEJO_STR" 2>/dev/null | grep '^FONT ')"
  vpf="$(printf '%s' "$VIEJO" | sed -n 's/.*pointSizeF=\([-0-9.]*\).*/\1/p')"
  if [ -z "$vpf" ]; then
    fallo "the break-on-purpose probe printed nothing: a vacuous pass proves nothing"
  elif python3 -c "import sys; sys.exit(0 if float('$vpf') > 0 else 1)" 2>/dev/null; then
    fallo "the PIXEL form reads pointSizeF=$vpf: the assertion above cannot fail, so it proves nothing"
  else
    ok "break-on-purpose: the pixel form reads pointSizeF=$vpf -- exactly what printed the message"
  fi
else
  fallo "font-probe.cpp does NOT compile: the point-size claim would be unproven"
fi
rm -rf "$PROBE_DIR"

echo "  -- the declared LIMITS: what KDE cannot take, said out loud --"
afirmar_contiene "the generator DECLARES that tracking has no destination" "$GEN" "TRACKING"
afirmar_contiene "the generator names the Inter install command (SF Pro is not redistributable)" "$GEN" "inter-font"
afirmar_contiene "the generator declares the monospaced family it falls back to" "$GEN" "FAMILIA_MONO"
if [ -f "$PROJECT/docs/HANDOFF.md" ] && grep -qE 'tracking|M4' "$PROJECT/docs/HANDOFF.md"; then
  ok "HANDOFF records the typography pass"
else
  fallo "HANDOFF does not record M4 (the milestone and its limits must survive the session)"
fi

echo "  -- the EVIDENCE the milestone asks for: a rendered comparison, not a drawing --"
if ls "$EVID"/*text*scale* >/dev/null 2>&1 || ls "$EVID"/*m4* >/dev/null 2>&1; then
  ok "there is a rendered text comparison in evidence/"
else
  fallo "no rendered text comparison in evidence/: M4's 'done when' asks for one"
fi
# It has to be a REAL render: a PNG whose two halves differ (the KDE default and the macOS scale
# cannot render identically, and an image that says they do is a drawing of an opinion).
if [ -f "$PROJECT/tools/render-type-comparison.py" ]; then
  ok "the render comparison has a generator (reproducible, not hand-drawn)"
else
  fallo "the evidence has no generator: tools/render-type-comparison.py is missing"
fi

echo "  -- regenerating must not change the tree (the generator is the source) --"
ANTES="$(mktemp -d)"
cp -r "$LNF" "$ANTES/"
if python3 "$GEN" >/dev/null 2>&1 && diff -r "$ANTES/KdeMacOS" "$LNF" >/dev/null 2>&1; then
  ok "regenerating the global theme leaves its defaults byte-identical"
else
  fallo "regenerating the global theme CHANGES it (the generator has drifted from the tree)"
fi
rm -rf "$ANTES"

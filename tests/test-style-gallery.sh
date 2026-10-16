# M6, slice 1: THE PRIMITIVE INSTRUMENT.
#
# WHY THIS EXISTS BEFORE ANY PRIMITIVE IS DRAWN. `docs/M6-QSTYLE-PLAN.md` says a primitive is only
# changed with its measurement in front, and lists this as slice 1 for that reason: the plan's
# measurement, the skeleton's `DIFF: 0 of 19800`, is ONE widget. A style plugin is loaded by every
# application on the desktop, so "which primitives do we differ on, by how much, and what does Qt
# ask each control for" has to be a TABLE before it can be a decision.
#
# WHAT THIS FILE ASSERTS, and each one is a way the instrument could lie:
#   1. the gallery renders EVERY declared primitive, and reports a DIFFERENCE PER WIDGET, not one
#      number for a collage -- a single number for many widgets hides one of them changing;
#   2. today every difference is ZERO, because the skeleton delegates every primitive;
#   3. every difference is a difference OF something: `PAINTED base>0` and `PAINTED ours>0`. This is
#      the trap the first probe fell into -- it counted non-white pixels, the widget's own
#      background covered the canvas, and `19800 of 19800` would have been green for a style that
#      painted NOTHING. Two identical blank canvases also differ by zero;
#   4. Qt's metrics per primitive are REPORTED (pixelMetric, sizeFromContents, subControlRect and
#      the size hint), because without the "before" the next slice cannot say "we changed it";
#   5. every primitive is EITHER backed by a macOS reference from `tokens/tokens-sizes.toml` OR on
#      the declared list of primitives that have NO reference. A primitive that is silently in
#      neither is a primitive somebody will redraw from taste.
ST="$PROJECT/style-kde-macos"
GALERIA="$ST/build/bin/primitive-gallery"
FUENTE="$ST/tests/primitive-gallery.cpp"

# The primitives the gallery must render. This list is the CONTRACT between the test and the tool:
# adding a control here without teaching the tool to draw it fails, which is the point.
WIDGETS="pushbutton pushbutton-default pushbutton-disabled checkbox checkbox-checked
checkbox-disabled radio radio-checked slider scrollbar combobox tabbar menubar menu lineedit
lineedit-focused progressbar listview-selected tableheader"

# The primitives with NO macOS reference in the kit's Sizes collection. They are listed HERE, in the
# test and not only in a document, so the list cannot grow silently: a slice that finds a reference
# for one of these must remove it from this list, and a slice that adds a control with no reference
# must add it and say so.
SIN_REFERENCIA="scrollbar tabbar menubar progressbar listview-selected tableheader"

# THE PRIMITIVES THIS SLICE MOVED, and the list is the contract exactly like the one above: slice 2
# is the push button, so these three rows -- and ONLY these three -- are allowed to differ from the
# base. A fourth row moving means the slice touched a control nobody measured, which is the failure
# this whole instrument exists to make visible.
CAMBIADOS="pushbutton pushbutton-default pushbutton-disabled"

es_cambiado() { # es_cambiado <primitivo>
  case " $CAMBIADOS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

echo "  -- the instrument exists and asks Qt the questions a style decision needs --"
afirmar_existe "the gallery source exists" "$FUENTE"
# The three families of metric the plan names. A gallery that rendered widgets but asked Qt nothing
# would measure the pixels and leave the next slice to guess the sizes.
afirmar_codigo "it asks Qt for the pixel metrics" "$FUENTE" 'pixelMetric'
afirmar_codigo "and for the content sizes" "$FUENTE" 'sizeFromContents'
afirmar_codigo "and for the sub-control rectangles" "$FUENTE" 'subControlRect'
# The whole point is per-widget: one number for a collage is the plan's stated mistake.
afirmar_codigo "it renders one widget at a time (per-widget difference)" "$FUENTE" 'renderOne'

echo "  -- it builds with the component --"
if [ ! -x "$GALERIA" ]; then
  if ! (cd "$ST" && timeout 110 ./build.sh) >/dev/null 2>&1; then
    fallo "style-kde-macos/build.sh failed: $(cd "$ST" && timeout 110 ./build.sh 2>&1 | tail -3 | tr '\n' ' ')"
  fi
fi
afirmar_existe "the gallery was built" "$GALERIA"

echo "  -- it runs offscreen, with no screen and no session --"
salida=""
rc=1
if [ -x "$GALERIA" ]; then
  salida="$(QT_QPA_PLATFORM=offscreen QT_PLUGIN_PATH="$ST/build" timeout 120 "$GALERIA" 2>&1)"
  rc=$?
fi
# The tool ASSERTS the delegation property and exits 5 the moment a primitive stops being a no-op.
# Slice 2 is that moment, so "5 with exactly the declared set" is the EXPECTED answer now -- not a
# reason to weaken the check: the tool still reports which and how many, and the rows below pin them.
afirmar_igual "the gallery reports that a primitive moved (exit 5)" "5" "$rc"
afirmar_contiene "and it counts exactly the declared ones" <(printf '%s\n' "$salida") "^CHANGED: 3\$"

echo "  -- every declared primitive is rendered, and each one is a real render --"
for w in $WIDGETS; do
  linea="$(printf '%s\n' "$salida" | grep -E "^WIDGET ${w} " | head -1)"
  if [ -z "$linea" ]; then
    fallo "the gallery did not report the primitive '$w'"
    continue
  fi
  pbase="$(sed -n 's/.*PAINTED base=\([0-9]*\).*/\1/p' <<<"$linea")"
  pours="$(sed -n 's/.*ours=\([0-9]*\).*/\1/p' <<<"$linea")"
  dif="$(sed -n 's/.*DIFF \([0-9]*\) of .*/\1/p' <<<"$linea")"
  # 3. Both renders must have painted. Two blank canvases are identical too, and that identity
  #    proves nothing about a style.
  if [ -n "$pbase" ] && [ "$pbase" -gt 0 ] 2>/dev/null && [ -n "$pours" ] && [ "$pours" -gt 0 ] 2>/dev/null; then
    ok "'$w' painted under both styles (base=$pbase ours=$pours)"
  else
    fallo "'$w' reported no painted pixels: $linea"
  fi
  # 2. The per-widget difference. Slice 2 moved the push button on purpose, so THAT row must have
  #    moved and every other row must still be zero. A diff of -1 is the tool saying the two renders
  #    were not the same size, which is not a difference anybody measured and is caught here.
  if es_cambiado "$w"; then
    if [ -n "$dif" ] && [ "$dif" -gt 0 ] 2>/dev/null; then
      ok "'$w' moved by $dif pixels, which is slice 2's declared change"
    else
      fallo "'$w' is declared as changed by this slice but differs by '${dif:-?}'"
    fi
  else
    afirmar_igual "'$w' still differs from the base by ZERO pixels" "0" "${dif:-?}"
  fi
done

echo "  -- and Qt's metrics per primitive are on the record --"
for w in $WIDGETS; do
  afirmar_contiene "'$w' reports its metrics" <(printf '%s\n' "$salida") "^METRIC ${w} "
  # And the metrics are a no-op for every control this slice did NOT touch: a primitive whose metrics
  # move while its pixels do not is a change nobody measured. The button's are expected to move, and
  # the exact values it answers are asserted against the token below, not merely counted.
  if es_cambiado "$w"; then
    negar "'$w' is declared changed, so its metrics MUST have moved" \
      grep -qE "^METRICDIFF ${w} 0\$" <(printf '%s\n' "$salida")
  else
    afirmar_contiene "'$w' answers the SAME metrics as the base" <(printf '%s\n' "$salida") "^METRICDIFF ${w} 0\$"
  fi
done
# The metrics are not just counted, they have four families: the "before" the next slice needs.
afirmar_contiene "the size hints are reported" <(printf '%s\n' "$salida") '^METRIC \S+ sizeHint='
afirmar_contiene "the pixel metrics are reported" <(printf '%s\n' "$salida") '^METRIC \S+ pixelMetric\(PM_'
afirmar_contiene "the sub-control rectangles are reported" <(printf '%s\n' "$salida") '^METRIC \S+ subControlRect\(CC_'
# `subElementRect` is not a duplicate of the line above: Qt 6 has NO complex control for a button, a
# checkbox or a radio button (measured in <QtWidgets/qstyle.h>), so THEIR geometry only exists as
# sub-elements. A table with only sub-controls would have left the most visible control with no
# rectangle at all.
afirmar_contiene "the sub-element rectangles are reported too (buttons are not complex controls)" \
  <(printf '%s\n' "$salida") '^METRIC \S+ subElementRect\(SE_'

echo "  -- the numbers that moved are the token's, and the token is read from the file --"
# The reference is read HERE, from the same collection the rest of the project uses, so this cannot
# drift into a constant somebody remembered: the assertion compares what the STYLE ANSWERS against
# what the KIT SAYS, and both come out of the same file. A slice that changed a button to 22 px
# because it looked better fails here, and it fails with the token's number in the message.
altura_medio="$(python3 -c "import tomllib;print(tomllib.load(open('$PROJECT/tokens/tokens-sizes.toml','rb'))['global']['height']['medium'])" 2>/dev/null)"
# The reference itself is asserted to exist: a test that reads a missing value and compares "" with
# "" would pass over a token that had been deleted.
afirmar_contiene "the token [global] height.medium is a number (the assertion needs a reference, not a hole)" \
  <(printf '%s\n' "$altura_medio") '^[0-9][0-9]*$'
afirmar_contiene "our push button's height IS that token" \
  <(printf '%s\n' "$salida") "^OURS pushbutton sizeHint=[0-9]+x${altura_medio}\$"
afirmar_contiene "and its sizeFromContents answers the same height" \
  <(printf '%s\n' "$salida") "^OURS pushbutton sizeFromContents\(CT_PushButton\)=[0-9]+x${altura_medio}\$"
# ONLY the declared primitives report a moved value. The OURS lines ARE the moved metrics, so their
# count is the contract's arithmetic (3 buttons x 2 metrics), not a number to keep in step by hand.
afirmar_igual "only the declared primitives report a moved value" "6" "$(grep -cE '^OURS ' <<<"$salida")"
for w in $WIDGETS; do
  if es_cambiado "$w"; then
    afirmar_contiene "'$w' reports the value it moved to" <(printf '%s\n' "$salida") "^OURS ${w} "
  else
    negar "'$w' reports no moved value" grep -qE "^OURS ${w} " <(printf '%s\n' "$salida")
  fi
done

echo "  -- every primitive is backed by a reference, or declared to have none --"
# The reference lives in the tokens the project already extracted; the instrument does not read TOML
# (that would be a second parser), so the mapping is checked HERE, against the real file.
# The TOML is read with tomllib and the section is walked as a PATH: `[slider.knob_non_ticked_slider]`
# is a nested table, not a key whose name contains a dot, and looking it up as a flat key reported a
# reference that exists as missing. That was this file's own first failure, caught by running it.
problema="$(python3 - "$PROJECT" "$WIDGETS" "$SIN_REFERENCIA" <<'PY' 2>&1
import sys, pathlib, tomllib

project, widgets, sin_ref = pathlib.Path(sys.argv[1]), sys.argv[2].split(), set(sys.argv[3].split())
# Which Sizes section backs each primitive. `None` means "declared to have no reference".
mapa = {
    "pushbutton": "button", "pushbutton-default": "button", "pushbutton-disabled": "button",
    "checkbox": "checkboxes", "checkbox-checked": "checkboxes", "checkbox-disabled": "checkboxes",
    "radio": "radio", "radio-checked": "radio",
    "slider": "slider.knob_non_ticked_slider",
    "combobox": "combo_button", "menu": "menu", "lineedit": "fields", "lineedit-focused": "fields",
    "scrollbar": None, "tabbar": None, "menubar": None, "progressbar": None,
    "listview-selected": None, "tableheader": None,
}

def seccion(doc, ruta):
    nodo = doc
    for parte in ruta.split("."):
        if not isinstance(nodo, dict) or parte not in nodo:
            return None
        nodo = nodo[parte]
    return nodo if isinstance(nodo, dict) and nodo else None

sizes = tomllib.load(open(project / "tokens" / "tokens-sizes.toml", "rb"))
faltan = []
for w in widgets:
    if w not in mapa:
        faltan.append(f"{w}: not mapped to a reference and not declared as having none")
        continue
    sec = mapa[w]
    if sec is None:
        if w not in sin_ref:
            faltan.append(f"{w}: has no reference but is not on the declared list")
        continue
    if seccion(sizes, sec) is None:
        faltan.append(f"{w}: the reference section '{sec}' is missing or empty")
    if w in sin_ref:
        faltan.append(f"{w}: declared as having no reference, but '{sec}' backs it")
for extra in sorted(sin_ref - set(widgets)):
    faltan.append(f"{extra}: declared as having no reference but is not in the gallery")
print("; ".join(faltan))
PY
)"
if [ -z "$problema" ]; then
  ok "each primitive is either backed by a Sizes reference or declared to have none"
else
  fallo "the reference coverage is incomplete: $problema"
fi

echo "  -- the instrument can write the baseline (a temp file, never the repository) --"
if [ -x "$GALERIA" ]; then
  tmpbase="$(mktemp)"
  QT_QPA_PLATFORM=offscreen QT_PLUGIN_PATH="$ST/build" timeout 120 "$GALERIA" --baseline "$tmpbase" >/dev/null 2>&1
  rcbase=$?
  # EXIT 5 IS THE TOOL'S OWN REPORT, not a failure: it means "a primitive moved", which is true now,
  # and the file is still written. Calling that a failure would force the tool to stop reporting the
  # very thing this slice is here to measure.
  if [ "$rcbase" = "0" ] || [ "$rcbase" = "5" ]; then
    ok "the gallery writes a baseline file (exit $rcbase is its own report)"
  else
    fallo "the gallery could not write a baseline (exit $rcbase)"
  fi
  faltan_base=""
  for w in $WIDGETS; do
    grep -qE "^METRIC ${w} " "$tmpbase" 2>/dev/null || faltan_base="$faltan_base $w"
  done
  if [ -z "$faltan_base" ]; then
    ok "the baseline carries a row for every primitive"
  else
    fallo "the baseline is missing:$faltan_base"
  fi
  rm -f "$tmpbase"
  # And the drawing: OUR gallery, not a screenshot of anybody's desktop.
  tmpimg="$(mktemp -u).png"
  QT_QPA_PLATFORM=offscreen QT_PLUGIN_PATH="$ST/build" timeout 120 "$GALERIA" --render "$tmpimg" >/dev/null 2>&1
  rcimg=$?
  if { [ "$rcimg" = "0" ] || [ "$rcimg" = "5" ]; } && [ -s "$tmpimg" ]; then
    ok "the gallery can draw itself to a PNG (the evidence is ours)"
  else
    fallo "the gallery could not render its PNG (exit $rcimg)"
  fi
  rm -f "$tmpimg"
fi

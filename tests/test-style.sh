# M6, first slice: the QStyle skeleton.
#
# WHAT THIS FILE IS FOR, and what it deliberately does NOT assert.
#
# The ROADMAP's M6 is a QStyle of our own so native Qt applications are drawn like macOS without
# Kvantum. That is one to three months of work, so the first slice delivers a SKELETON and stops:
# the plugin loads, the style is selectable, and NOTHING is redrawn yet. The property that makes
# that safe is that every primitive is still the base style's, so this file asserts the ABSENCE of
# overrides -- a skeleton with one half-finished button in it is worse than no skeleton, because it
# breaks applications and cannot be told apart from one that works.
#
# The three claims the slice has to prove, and how:
#   1. the plugin compiles            -> build.sh, then the .so exists
#   2. its metadata is valid          -> the JSON is parsed and its Keys are the ones we select by
#   3. it DRAWS with the style set    -> a Qt app under the OFFSCREEN platform renders a widget and
#      without crashing                 reports the pixels it painted, in its own process
#
# Claim 3 is the one that matters: "it is selectable without breaking applications" is half of
# M6's done criterion, and a plugin that loads but crashes on the first paint would satisfy claims
# 1 and 2 while failing the thing the criterion actually asks for.
ST="$PROJECT/style-kde-macos"

echo "  -- the plan is written, and it is a plan and not a wish --"
afirmar_existe "docs/M6-QSTYLE-PLAN.md exists" "$PROJECT/docs/M6-QSTYLE-PLAN.md"
afirmar_contiene "it decides the base style, with the measurement" "$PROJECT/docs/M6-QSTYLE-PLAN.md" 'Breeze'
afirmar_contiene "it says how the style is selected" "$PROJECT/docs/M6-QSTYLE-PLAN.md" 'widgetStyle'
afirmar_contiene "it says how to go back" "$PROJECT/docs/M6-QSTYLE-PLAN.md" 'rollback'
afirmar_contiene "it slices the rest of M6" "$PROJECT/docs/M6-QSTYLE-PLAN.md" 'slice'
afirmar_contiene "it records what is still OPEN rather than inventing it" \
  "$PROJECT/docs/M6-QSTYLE-PLAN.md" 'OPEN'

echo "  -- the plugin declares itself the way Qt 6 needs --"
# The measurements behind these four assertions are in the plan: the IID comes from the Qt header
# itself (qstyleplugin.h defines QStyleFactoryInterface_iid), the Keys are what QStyleFactory
# matches against, and QProxyStyle is the class whose whole purpose is delegating to a base.
afirmar_existe "src/metadata.json exists" "$ST/src/metadata.json"
afirmar_existe "src/macosstyle.h exists" "$ST/src/macosstyle.h"
afirmar_existe "src/macosstyle.cpp exists" "$ST/src/macosstyle.cpp"
afirmar_codigo "the plugin IS a QStylePlugin" "$ST/src/macosstyle.h" 'QStylePlugin'
afirmar_codigo "declared with Qt's own style factory IID" "$ST/src/macosstyle.h" 'QStyleFactoryInterface_iid'
afirmar_codigo "and the style is a QProxyStyle (delegation is the point)" "$ST/src/macosstyle.h" 'QProxyStyle'
afirmar_codigo "the metadata file is what moc embeds" "$ST/src/macosstyle.h" 'Q_PLUGIN_METADATA'
afirmar_codigo "the base is RESOLVED, not assumed to exist" "$ST/src/macosstyle.cpp" 'QStyleFactory::keys'

# The JSON is parsed, not grepped: a metadata file that is almost right is a plugin Qt refuses to
# load, and `grep Keys` cannot tell the difference.
if python3 - "$ST/src/metadata.json" <<'PY' 2>/dev/null
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["Keys"] == ["KdeMacOS"], data
PY
then
  ok "metadata.json is valid JSON and its Keys are exactly [KdeMacOS]"
else
  fallo "metadata.json is not valid JSON with Keys == [\"KdeMacOS\"]"
fi

echo "  -- the style overrides ONLY what a landed slice has measured --"
# This is the assertion that keeps the style honest. Every one of these is a drawing or measuring
# primitive that changes what an application LOOKS like; overriding one without its measurement is
# how a half-finished style breaks the desktop.
#
# Slice 2 landed `sizeFromContents` and `drawControl` (the push button), so those two are no longer
# absent -- the assertion MOVES WITH THE SLICE and keeps naming the ones that must stay absent. It is
# not weakened: the list is still checked, and the two that landed are asserted BY NAME just below.
#
# It asks `codigo_contiene`, which IGNORES COMMENTS, and that is not a detail: the header's own
# comment lists these primitives to explain WHY they are absent, and a plain grep counted the
# explanation as the deed (it reported two overrides that do not exist). Same lesson as the
# harness's, in the other direction.
# Slice 2 landed `sizeFromContents` and `drawControl` (the push button), and slice 3 landed
# `pixelMetric` and `drawPrimitive` (the checkbox and the radio button), so those four are no longer
# absent -- the assertion MOVES WITH THE SLICE and keeps naming the ones that must stay absent. It is
# not weakened: the list is still checked, and the four that landed are asserted BY NAME just below.
negar "no primitive beyond the landed slices is overridden" \
  codigo_contiene "$ST/src/macosstyle.h" 'drawComplexControl|subElementRect|standardIcon|styleHint'
afirmar_codigo "slice 2's size override is the one that landed" "$ST/src/macosstyle.h" 'sizeFromContents'
afirmar_codigo "and so is its drawing override" "$ST/src/macosstyle.h" 'drawControl'
afirmar_codigo "slice 3's metric override landed" "$ST/src/macosstyle.h" 'pixelMetric'
afirmar_codigo "and slice 3's primitive override too" "$ST/src/macosstyle.h" 'drawPrimitive'

echo "  -- it builds --"
# The build runs here because 'the plugin compiles' is one of the three claims, and a claim that is
# only ever made in prose is the kind this repository has paid for. It is skipped when the .so is
# already NEWER than every source, so a warm tree does not pay for cmake on every suite run.
so="$ST/build/styles/kdemacosstyle.so"
necesita=1
if [ -f "$so" ]; then
  necesita=0
  for fuente in "$ST"/src/*.cpp "$ST"/src/*.h "$ST"/src/metadata.json "$ST"/CMakeLists.txt; do
    [ -f "$fuente" ] || continue
    [ "$fuente" -nt "$so" ] && necesita=1
  done
fi
if [ "$necesita" = "1" ]; then
  if ! (cd "$ST" && timeout 110 ./build.sh) >/dev/null 2>&1; then
    fallo "style-kde-macos/build.sh failed: $(cd "$ST" && timeout 110 ./build.sh 2>&1 | tail -3 | tr '\n' ' ')"
  fi
fi
afirmar_existe "the plugin was built" "$so"

echo "  -- and a Qt application draws with it, under the offscreen platform --"
# OFFSCREEN, so this needs no screen, no session and no user: it is the same platform the project
# already uses for its other Qt probes. The probe reports what it did and exits non-zero if the
# style could not be created or nothing was painted.
sonda="$ST/build/bin/style-probe"
afirmar_existe "the probe was built" "$sonda"
if [ -x "$sonda" ]; then
  salida="$(QT_QPA_PLATFORM=offscreen QT_PLUGIN_PATH="$ST/build" timeout 60 "$sonda" 2>&1)"
  rc=$?
  afirmar_igual "the probe exits cleanly (it did not crash)" "0" "$rc"
  afirmar_contiene "QStyleFactory sees the style by its key" <(printf '%s\n' "$salida") 'KEYS.*KdeMacOS'
  afirmar_contiene "the style could be created from the factory" <(printf '%s\n' "$salida") 'CREATE: ok'
  afirmar_contiene "and it chains to a real base style" <(printf '%s\n' "$salida") 'BASE: (Breeze|Fusion)'
  # PAINTED reports both renders. The base one is the control: if IT painted nothing, an identical
  # difference would be a comparison of two blank canvases and would prove nothing.
  pintados="$(printf '%s\n' "$salida" | sed -n 's/^PAINTED: base=\([0-9]*\) ours=\([0-9]*\)/\1 \2/p')"
  if [ -n "$pintados" ] && [ "${pintados%% *}" -gt 0 ] 2>/dev/null; then
    ok "both renders painted the controls ($pintados pixels, base first)"
  else
    fallo "the probe reported no painted pixels: $salida"
  fi
  # THE ASSERTION THE SLICE IS REALLY ABOUT: our style must draw IDENTICALLY to the base, because it
  # delegates every primitive. This is what "selectable without breaking applications" means while
  # the skeleton is a skeleton -- and the day a slice implements a primitive, this line is the one
  # that slice replaces, WITH the measurement it owes.
  afirmar_contiene "and the two renders are IDENTICAL (delegating everything is a no-op)" \
    <(printf '%s\n' "$salida") '^DIFF: 0 of '
fi

echo "  -- the installer knows about it, so it can be installed and undone --"
afirmar_codigo "install.sh installs the style" "$PROJECT/install.sh" 'kdemacosstyle'
afirmar_codigo "and puts it where Qt looks for styles" "$PROJECT/install.sh" 'plugins/styles'
afirmar_codigo "with the plugin path set for the session" "$PROJECT/install.sh" 'QT_PLUGIN_PATH'
# The golden rule of that installer: it never escalates and never writes outside $HOME. A style that
# needs sudo to install is a style the user cannot undo with one command.
negar "install.sh does not invoke sudo for the style" \
  grep -qE 'sudo.*(kdemacosstyle|plugins/styles)' "$PROJECT/install.sh"
afirmar_contiene "the README explains how to select it and undo it" "$ST/README.md" 'rollback'

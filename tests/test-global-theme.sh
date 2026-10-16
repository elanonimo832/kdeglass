# M3 — the Plasma GLOBAL theme (LookAndFeel) and the PlasmaStyle it links.
#
# docs/ROADMAP.md: a global theme that carries ONE part and leaves the rest half done does not
# meet M3. So most of this file is about the LINK and not about the files: every theme name the
# `defaults` writes down has to exist, and the installer has to be able to FIND it.
#
# WHAT THIS CAUGHT, measured before it was fixed: `install.sh` had `SALIDA="$AQUI/salida"` while
# every generator writes to `output/`. `install.sh plan` printed "source does not exist" for ALL
# SIX entries, so the installer installed nothing and said nothing. The assertion that walks the
# plan forbids that sentence, so the two names cannot drift apart again.

LNF="$PROJECT/output/look-and-feel/KdeMacOS"
DT="$PROJECT/output/desktoptheme/KdeMacOS"
DECO="$PROJECT/output/aurorae/KdeMacOS"
ESQUEMAS="$PROJECT/output/color-schemes"

# Read the REAL metadata: an assertion on a name that also appears in a comment is the mistake
# this project has paid for most often, and these files are half comments.
json_get() {
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d=d[k]
print(d)
' "$1" "$2" 2>/dev/null
}

# KDE writes `contents/defaults` with [file][group] sections, which no INI reader here parses.
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

echo "  -- the global theme package (LookAndFeel) --"
afirmar_existe "the LookAndFeel package exists" "$LNF"
afirmar_existe "  metadata.json" "$LNF/metadata.json"
afirmar_existe "  contents/defaults (the file that applies the parts)" "$LNF/contents/defaults"

M="$LNF/metadata.json"
afirmar_igual "KPackageStructure is Plasma/LookAndFeel" "Plasma/LookAndFeel" "$(json_get "$M" KPackageStructure)"
afirmar_igual "the Id is the project's" "KdeMacOS" "$(json_get "$M" KPlugin.Id)"
afirmar_igual "the Name is the project's" "KdeMacOS" "$(json_get "$M" KPlugin.Name)"
# The version is the PROJECT's, and the proof is that it is the SAME number the decoration
# declares: a version written twice drifts, so one is checked against the other.
V_DECO="$(sed -n 's/^X-KDE-PluginInfo-Version=//p' "$DECO/metadata.desktop")"
afirmar_igual "the decoration declares the project version" "0.1.0" "$V_DECO"
afirmar_igual "and the global theme declares the SAME version" "$V_DECO" "$(json_get "$M" KPlugin.Version)"
afirmar "the metadata declares a Description" test -n "$(json_get "$M" KPlugin.Description)"
afirmar "the metadata declares a License (no Apple material is redistributed)" test -n "$(json_get "$M" KPlugin.License)"
afirmar "the metadata declares its Authors" test -n "$(json_get "$M" KPlugin.Authors)"

echo "  -- the PlasmaStyle it links --"
afirmar_existe "the desktop theme exists" "$DT"
afirmar_existe "  metadata.json" "$DT/metadata.json"
afirmar_existe "  colors (its own palette)" "$DT/colors"
afirmar_existe "  plasmarc" "$DT/plasmarc"
afirmar_igual "it is a Plasma 6 desktop theme (X-Plasma-API)" "5.0" "$(json_get "$DT/metadata.json" X-Plasma-API)"
afirmar_igual "  its Id is the project's" "KdeMacOS" "$(json_get "$DT/metadata.json" KPlugin.Id)"

echo "  -- every part the defaults names is really there --"
D="$LNF/contents/defaults"
CS="$(ini_get "$D" kdeglobals General ColorScheme)"
afirmar_igual "the defaults select our light colour scheme" "KdeMacosLight" "$CS"
afirmar_existe "  and that scheme is in the tree" "$ESQUEMAS/$CS.colors"
PL="$(ini_get "$D" plasmarc Theme name)"
afirmar_igual "the defaults select our PlasmaStyle" "KdeMacOS" "$PL"
afirmar_existe "  and that style is in the tree" "$PROJECT/output/desktoptheme/$PL"
DE="$(ini_get "$D" kwinrc org.kde.kdecoration2 theme)"
afirmar_igual "the defaults select our window decoration" "__aurorae__svg__KdeMacOS" "$DE"
afirmar_existe "  and that decoration is in the tree" "$DECO"
# THE PARTS WE DO NOT SHIP MUST NOT BE OURS. An icon theme of our own does not exist until M5,
# and naming one here would leave the user without icons: the theme has to point at what is there.
afirmar_igual "the icon theme it selects is the KDE default, which exists (M5 ships none yet)" \
  "breeze" "$(ini_get "$D" kdeglobals Icons Theme)"
afirmar "and that icon theme is really installed here (naming a missing one breaks the desktop)" \
  test -d "/usr/share/icons/$(ini_get "$D" kdeglobals Icons Theme)"

echo "  -- the installer can FIND what it has to install --"
PLAN="$(mktemp)"
XDG_CONFIG_HOME="$(mktemp -d)" XDG_DATA_HOME="$(mktemp -d)" XDG_STATE_HOME="$(mktemp -d)" \
  timeout 60 bash "$PROJECT/install.sh" plan >"$PLAN" 2>&1
negar "no mapped source is missing (this is the salida/output bug)" \
  grep -q "source does not exist" "$PLAN"
afirmar_contiene "and the plan knows about the global theme" "$PLAN" 'look-and-feel/KdeMacOS'
afirmar_contiene "and about the PlasmaStyle" "$PLAN" 'desktoptheme/KdeMacOS'

echo "  -- reproducibility: regenerate and compare --"
ANTES="$(mktemp -d)"
cp -a "$LNF" "$ANTES/lnf"
cp -a "$DT" "$ANTES/dt"
python3 "$PROJECT/tools/generate-global-theme.py" >/dev/null 2>&1
GENERADOR=$?
# VERIFY THE TOOL BEFORE THE OBJECT (METHODOLOGY rule 4). The colour-scheme check in
# test-artifacts.sh calls its generator with NO arguments, and that generator then prints its
# help and returns 2: nothing is regenerated and the comparison is a same-file formality. This
# one is called the way it is meant to be called, and its exit code is PART of the test.
if [ "$GENERADOR" = "0" ]; then
  ok "the generator runs with no arguments, so the comparison below is real"
else
  fallo "the generator FAILED (exit $GENERADOR): nothing was regenerated, so this is a false green"
fi
if diff -r "$ANTES/lnf" "$LNF" >/dev/null 2>&1; then
  ok "regenerating the global theme is byte-identical"
else
  fallo "regenerating the global theme CHANGES it (the generator has drifted from the tree)"
fi
if diff -r "$ANTES/dt" "$DT" >/dev/null 2>&1; then
  ok "regenerating the PlasmaStyle is byte-identical"
else
  fallo "regenerating the PlasmaStyle CHANGES it"
fi
rm -rf "$ANTES" "$PLAN"

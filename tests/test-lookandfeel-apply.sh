#!/usr/bin/env bash
# M4 follow-up — the theme shipped a TYPE SCALE and an EFFECT SWITCH, and nothing applied them.
#
# MEASURED, not assumed. `plasma-apply-lookandfeel -a KdeMacOS` writes the theme's `defaults` into
# `$XDG_CONFIG_HOME/kdedefaults/<file>` -- the layer KDE reads as a FALLBACK -- and it silently
# DROPS the keys that do not fit there. Measured by applying into an isolated XDG_CONFIG_HOME and
# grepping the result, file by file: the SEVEN font keys (`[General] font`, `menuFont`,
# `toolBarFont`, `smallestReadableFont`, `fixed`, and `[WM] activeFont`/`inactiveFont`) and
# `[kwinrc][Plugins] macosglass2Enabled` land NOWHERE -- not in the user's config, not in the
# defaults layer. Everything else in the defaults does land in `kdedefaults/`.
#
# That is the worst kind of miss: the package promises a type scale and an effect switch, the
# installer copies it, the tool reports success, and neither of the two ever happens. So the
# installer reads the GENERATED `defaults` (the one source of truth, the same file the map
# installs) and writes, with kwriteconfig6, ONLY the keys the tool did not carry.
#
# Everything here runs with an ISOLATED XDG_CONFIG_HOME and XDG_DATA_HOME. The user's session is
# never touched: that is not an installer's decision to make from a test.

echo "  -- the installer applies what plasma-apply-lookandfeel drops --"

AISLADO="$(mktemp -d)"
# NO `trap ... EXIT` HERE: run-one.sh uses that trap to write the counter this file has to report,
# and a trap set here REPLACES it, so the runner sees "died without reporting a counter" even
# though every assertion passed. Cleanup is a plain call at the end of the file.
export XDG_CONFIG_HOME="$AISLADO/config"
export XDG_DATA_HOME="$AISLADO/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

# Read a key from the PLAIN INI that KDE writes, with NO fallback: `kreadconfig6` merges the
# kdedefaults layer, so a key the tool dropped in there would look present when the user's own
# file does not have it. This test has to see the user's file.
plano_get() { # plano_get <file> <group> <key>
  awk -v g="$2" -v k="$3" '
    { l = $0; sub(/\r$/, "", l) }
    /^\[/ { s = l; sub(/^\[/, "", s); sub(/\]$/, "", s); dentro = (s == g); next }
    dentro && index(l, k"=") == 1 { sub("^" k"=", "", l); print l; exit }
  ' "$1" 2>/dev/null
}

# The same reader as the other M3 tests, for the `[file][group]` of a look-and-feel defaults.
ini_get() { # ini_get <file> <section> <group> <key>
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

# A key of the USER'S, written BEFORE anything else, to prove the installer does not walk over
# what is not the theme's. Applying a theme is not an excuse to rewrite the world.
timeout 5 kwriteconfig6 --file kdeglobals --group KDE --key ClaveDelUsuario valor-del-usuario >/dev/null 2>&1

# 1. The tool first, exactly as the user's documented flow runs it, so the kdedefaults layer
#    exists and this test exercises the REAL mechanism instead of a hypothetical one.
if command -v plasma-apply-lookandfeel >/dev/null 2>&1; then
  timeout 60 plasma-apply-lookandfeel -a KdeMacOS >/dev/null 2>&1
fi

# 2. The installer.
bash "$PROJECT/install.sh" aplicar --si >/dev/null 2>&1

DEFAULTS="$PROJECT/output/look-and-feel/KdeMacOS/contents/defaults"

# 3. Every font key of the generated defaults has to END UP in the user's kdeglobals with the SAME
#    value, compared one by one against the FILE -- never against a string remembered here, or
#    this test would pass the day the defaults change and the installer does not.
while read -r grupo clave; do
  [ -n "$clave" ] || continue
  esperado="$(ini_get "$DEFAULTS" kdeglobals "$grupo" "$clave")"
  obtenido="$(plano_get "$XDG_CONFIG_HOME/kdeglobals" "$grupo" "$clave")"
  afirmar_igual "kdeglobals [$grupo] $clave carries the defaults' value" "$esperado" "$obtenido"
done <<'CLAVES'
General font
General menuFont
General toolBarFont
General smallestReadableFont
General fixed
WM activeFont
WM inactiveFont
CLAVES

# 4. The effect switch: the tool drops it too, and without it the theme does not turn the effect on.
afirmar_igual "kwinrc [Plugins] macosglass2Enabled lands" "true" \
  "$(plano_get "$XDG_CONFIG_HOME/kwinrc" Plugins macosglass2Enabled)"

# 5. And the user's own key survives.
afirmar_igual "a key that is NOT the theme's survives" "valor-del-usuario" \
  "$(plano_get "$XDG_CONFIG_HOME/kdeglobals" KDE ClaveDelUsuario)"

# 6. The rollback has to undo what the installer wrote, or "full revert" is a half revert.
bash "$PROJECT/install.sh" rollback >/dev/null 2>&1
afirmar_igual "rollback removes the font key it wrote" "" \
  "$(plano_get "$XDG_CONFIG_HOME/kdeglobals" General font)"

rm -rf "$AISLADO"
